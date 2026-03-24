import AppKit
import ApplicationServices
import DesktopflowCore
import Foundation

public enum CoreGraphicsInputError: LocalizedError {
    case unsupportedKey(String)
    case eventCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key):
            return "Unsupported key for playback: \(key)"
        case .eventCreationFailed(let kind):
            return "Failed to create \(kind) input event."
        }
    }
}

public final class CoreGraphicsInputDispatcher: @unchecked Sendable, InputDispatcher {
    private struct MousePathConfiguration {
        let speed: Double = 3600
        let minDuration: Double = 0.035
        let maxDuration: Double = 0.12
        let sampleInterval: Double = 0.004
        let curveHumpMin: Double = 25
        let curveHumpMax: Double = 120
        let controlPointJitter: Double = 15
        let jitterMagnitude: Double = 1.1
        let jitterFrequency: Double = 0.4
        let overshootChance: Double = 0.35
        let overshootDistanceThreshold: Double = 150
        let overshootMin: Double = 2
        let overshootMax: Double = 6
        let overshootDwellMs: UInt64 = 20
        let reactionDelayRangeMs: ClosedRange<UInt64> = 10...40
        let holdDelayRangeMs: ClosedRange<UInt64> = 50...90
    }

    private struct MouseMoveProfile {
        var speedScale: Double
        var curveHump: Double
        var skewX: Double
        var skewY: Double
        var controlJitter: Double
        var humpPolarity: Double
    }

    private let source: CGEventSource?
    private let mousePathConfiguration = MousePathConfiguration()

    public init() {
        self.source = CGEventSource(stateID: .hidSystemState)
    }

    public func focus(window: BoundWindow) async throws {
        if let pid = window.descriptor.ownerPID,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
            try await Task.sleep(for: .milliseconds(200))
            return
        }

        if let bundleID = window.descriptor.bundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate()
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    public func click(at point: ScreenPoint, button: MouseButton) async throws {
        let location = CGPoint(x: point.x, y: point.y)
        let eventTypes = mouseEventTypes(for: button)

        try await moveMouseNaturally(to: location, button: eventTypes.button)
        try await sleep(milliseconds: randomMilliseconds(in: mousePathConfiguration.reactionDelayRangeMs))
        try postMouseEvent(type: eventTypes.down, location: location, button: eventTypes.button)
        try await sleep(milliseconds: randomMilliseconds(in: mousePathConfiguration.holdDelayRangeMs))
        try postMouseEvent(type: eventTypes.up, location: location, button: eventTypes.button)
    }

    public func scroll(at point: ScreenPoint, deltaX: Int, deltaY: Int) async throws {
        guard deltaX != 0 || deltaY != 0 else { return }

        let location = CGPoint(x: point.x, y: point.y)
        try await moveMouseNaturally(to: location, button: .left)
        try await sleep(milliseconds: randomMilliseconds(in: mousePathConfiguration.reactionDelayRangeMs))

        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else {
            throw CoreGraphicsInputError.eventCreationFailed("scroll")
        }

        event.post(tap: .cghidEventTap)
    }

    public func drag(from startPoint: ScreenPoint, to endPoint: ScreenPoint, button: MouseButton, durationMs: Int) async throws {
        let startLocation = CGPoint(x: startPoint.x, y: startPoint.y)
        let endLocation = CGPoint(x: endPoint.x, y: endPoint.y)
        let eventTypes = mouseEventTypes(for: button)

        try await moveMouseNaturally(to: startLocation, button: eventTypes.button)
        try await sleep(milliseconds: randomMilliseconds(in: mousePathConfiguration.reactionDelayRangeMs))
        try postMouseEvent(type: eventTypes.down, location: startLocation, button: eventTypes.button)
        try await sleep(milliseconds: max(16, min(120, UInt64(max(0, durationMs) / 6))))
        try await moveMouseSegment(
            from: startLocation,
            to: endLocation,
            button: eventTypes.button,
            allowOvershoot: false,
            moveEventType: eventTypes.dragged,
            durationOverride: clamp(Double(max(0, durationMs)) / 1000, min: 0.08, max: 1.2)
        )
        try postMouseEvent(type: eventTypes.up, location: endLocation, button: eventTypes.button)
    }

    public func pressKey(keyCode: String, modifiers: [String], durationMs: Int) async throws {
        let resolvedKeyCode = try Self.resolveKeyCode(keyCode)
        let flags = Self.resolveModifierFlags(modifiers)

        let downEvent = try makeKeyEvent(keyCode: resolvedKeyCode, keyDown: true, flags: flags)
        let upEvent = try makeKeyEvent(keyCode: resolvedKeyCode, keyDown: false, flags: flags)
        downEvent.post(tap: .cghidEventTap)
        if durationMs > 0 {
            try await sleep(milliseconds: UInt64(durationMs))
        }
        upEvent.post(tap: .cghidEventTap)
    }

    private func postMouseEvent(type: CGEventType, location: CGPoint, button: CGMouseButton) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
            throw CoreGraphicsInputError.eventCreationFailed("mouse")
        }
        event.post(tap: .cghidEventTap)
    }

    private func moveMouseNaturally(to target: CGPoint, button: CGMouseButton) async throws {
        let start = currentMouseLocation()
        try await moveMouseSegment(from: start, to: target, button: button, allowOvershoot: true, moveEventType: .mouseMoved)
    }

    private func moveMouseSegment(
        from start: CGPoint,
        to target: CGPoint,
        button: CGMouseButton,
        allowOvershoot: Bool,
        moveEventType: CGEventType,
        durationOverride: Double? = nil
    ) async throws {
        let distance = hypot(target.x - start.x, target.y - start.y)
        if distance < 1 {
            try postMouseEvent(type: moveEventType, location: target, button: button)
            return
        }

        let profile = buildMoveProfile(distance: distance)
        let duration = durationOverride
            ?? clamp(
                distance / (mousePathConfiguration.speed * profile.speedScale),
                min: mousePathConfiguration.minDuration,
                max: mousePathConfiguration.maxDuration
            )

        if allowOvershoot,
           distance >= mousePathConfiguration.overshootDistanceThreshold,
           Double.random(in: 0...1) < mousePathConfiguration.overshootChance {
            let overshootTarget = target.pointAlongIncomingDirection(
                from: start,
                distance: Double.random(in: mousePathConfiguration.overshootMin...mousePathConfiguration.overshootMax)
            )
            try await moveMouseCurve(
                from: start,
                to: overshootTarget,
                button: button,
                profile: profile,
                duration: duration,
                moveEventType: moveEventType
            )
            try await sleep(milliseconds: mousePathConfiguration.overshootDwellMs)
            try await moveMouseSegment(
                from: overshootTarget,
                to: target,
                button: button,
                allowOvershoot: false,
                moveEventType: moveEventType,
                durationOverride: durationOverride
            )
            return
        }

        try await moveMouseCurve(
            from: start,
            to: target,
            button: button,
            profile: profile,
            duration: duration,
            moveEventType: moveEventType
        )
    }

    private func moveMouseCurve(
        from start: CGPoint,
        to target: CGPoint,
        button: CGMouseButton,
        profile: MouseMoveProfile,
        duration: Double,
        moveEventType: CGEventType
    ) async throws {
        let controls = buildBezierControls(from: start, to: target, profile: profile)
        let distance = hypot(target.x - start.x, target.y - start.y)
        let direction = normalizedDirection(from: start, to: target)
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let phase = Double.random(in: 0...(Double.pi * 2))
        let sampleCount = max(4, Int(ceil(duration / mousePathConfiguration.sampleInterval)))
        let sleepMs = max(1, UInt64((duration * 1000 / Double(sampleCount)).rounded()))

        for index in 1...sampleCount {
            let t = Double(index) / Double(sampleCount)
            let eased = humanEasing(t)
            var point = cubicBezierPoint(
                p0: start,
                p1: controls.0,
                p2: controls.1,
                p3: target,
                t: eased
            )

            let remaining = max(0, 1 - eased)
            let jitterWave = sin(((eased / max(mousePathConfiguration.jitterFrequency, 0.001)) + phase) * 2 * Double.pi)
            let jitterAmount = jitterWave * mousePathConfiguration.jitterMagnitude * remaining * min(1, distance / 80)
            point.x += perpendicular.x * jitterAmount
            point.y += perpendicular.y * jitterAmount

            if index == sampleCount {
                point = target
            }

            try postMouseEvent(type: moveEventType, location: point, button: button)
            try await sleep(milliseconds: sleepMs)
        }
    }

    private func mouseEventTypes(for button: MouseButton) -> (
        button: CGMouseButton,
        down: CGEventType,
        up: CGEventType,
        dragged: CGEventType
    ) {
        switch button {
        case .left:
            return (.left, .leftMouseDown, .leftMouseUp, .leftMouseDragged)
        case .right:
            return (.right, .rightMouseDown, .rightMouseUp, .rightMouseDragged)
        case .center:
            return (.center, .otherMouseDown, .otherMouseUp, .otherMouseDragged)
        }
    }

    private func currentMouseLocation() -> CGPoint {
        if let location = CGEvent(source: nil)?.location {
            return location
        }
        return NSEvent.mouseLocation
    }

    private func buildMoveProfile(distance: Double) -> MouseMoveProfile {
        let humpFactor = clamp(
            distance * 0.3,
            min: mousePathConfiguration.curveHumpMin,
            max: mousePathConfiguration.curveHumpMax
        )

        return MouseMoveProfile(
            speedScale: Double.random(in: 0.85...1.15),
            curveHump: humpFactor,
            skewX: Double.random(in: 0.8...1.2),
            skewY: Double.random(in: 0.8...1.2),
            controlJitter: Double.random(in: 5...mousePathConfiguration.controlPointJitter),
            humpPolarity: Bool.random() ? -1 : 1
        )
    }

    private func buildBezierControls(from start: CGPoint, to target: CGPoint, profile: MouseMoveProfile) -> (CGPoint, CGPoint) {
        let dx = target.x - start.x
        let dy = target.y - start.y
        let distance = hypot(dx, dy)
        guard distance >= 1 else {
            return (start, target)
        }

        let direction = CGPoint(x: dx / distance, y: dy / distance)
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let hump = profile.curveHump * profile.humpPolarity

        let controlOneDistance = distance * Double.random(in: 0.2...0.4)
        let controlOnePerpendicular = hump * Double.random(in: 0.4...0.8) * profile.skewX
        let controlOne = CGPoint(
            x: start.x + direction.x * controlOneDistance + perpendicular.x * controlOnePerpendicular + Double.random(in: -profile.controlJitter...profile.controlJitter),
            y: start.y + direction.y * controlOneDistance + perpendicular.y * controlOnePerpendicular + Double.random(in: -profile.controlJitter...profile.controlJitter)
        )

        let controlTwoDistance = distance * Double.random(in: 0.6...0.8)
        let controlTwoPerpendicular = hump * Double.random(in: 0.4...0.8) * profile.skewY
        let controlTwo = CGPoint(
            x: start.x + direction.x * controlTwoDistance + perpendicular.x * controlTwoPerpendicular + Double.random(in: -profile.controlJitter...profile.controlJitter),
            y: start.y + direction.y * controlTwoDistance + perpendicular.y * controlTwoPerpendicular + Double.random(in: -profile.controlJitter...profile.controlJitter)
        )

        return (controlOne, controlTwo)
    }

    private func normalizedDirection(from start: CGPoint, to target: CGPoint) -> CGPoint {
        let dx = target.x - start.x
        let dy = target.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else {
            return CGPoint.zero
        }
        return CGPoint(x: dx / distance, y: dy / distance)
    }

    private func humanEasing(_ t: Double) -> Double {
        if t < 0.2 {
            let accelerated = t / 0.2
            return accelerated * accelerated * 0.3
        }

        let decelerationProgress = (t - 0.2) / 0.8
        return 0.3 + 0.7 * (1 - pow(1 - decelerationProgress, 3))
    }

    private func cubicBezierPoint(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: Double) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let uuu = uu * u
        let tt = t * t
        let ttt = tt * t

        return CGPoint(
            x: (uuu * p0.x) + (3 * uu * t * p1.x) + (3 * u * tt * p2.x) + (ttt * p3.x),
            y: (uuu * p0.y) + (3 * uu * t * p1.y) + (3 * u * tt * p2.y) + (ttt * p3.y)
        )
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func randomMilliseconds(in range: ClosedRange<UInt64>) -> UInt64 {
        UInt64.random(in: range)
    }

    private func sleep(milliseconds: UInt64) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(Int(milliseconds)))
    }

    private func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) throws -> CGEvent {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw CoreGraphicsInputError.eventCreationFailed("keyboard")
        }
        event.flags = flags
        return event
    }

    private static func resolveModifierFlags(_ modifiers: [String]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier.lowercased() {
            case "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "control":
                flags.insert(.maskControl)
            case "option":
                flags.insert(.maskAlternate)
            default:
                break
            }
        }
    }

    private static func resolveKeyCode(_ key: String) throws -> CGKeyCode {
        if let rawCode = parseRecordedKeyCode(key) {
            return rawCode
        }

        let normalized = key.uppercased()
        if let special = specialKeyCodes[normalized] {
            return special
        }

        if let printable = printableKeyCodes[normalized] {
            return printable
        }

        throw CoreGraphicsInputError.unsupportedKey(key)
    }

    private static func parseRecordedKeyCode(_ key: String) -> CGKeyCode? {
        guard key.uppercased().hasPrefix("KEY_") else { return nil }
        guard let code = UInt16(key.dropFirst(4)) else { return nil }
        return CGKeyCode(code)
    }

    private static let specialKeyCodes: [String: CGKeyCode] = [
        "SPACE": 49,
        "RETURN": 36,
        "TAB": 48,
        "ESCAPE": 53,
        "DELETE": 51,
        "LEFT": 123,
        "RIGHT": 124,
        "DOWN": 125,
        "UP": 126
    ]

    private static let printableKeyCodes: [String: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
        "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47
    ]
}

private extension CGPoint {
    func pointAlongIncomingDirection(from start: CGPoint, distance: Double) -> CGPoint {
        let dx = x - start.x
        let dy = y - start.y
        let magnitude = hypot(dx, dy)
        guard magnitude > 0 else { return self }
        return CGPoint(
            x: x + (dx / magnitude) * distance,
            y: y + (dy / magnitude) * distance
        )
    }
}
