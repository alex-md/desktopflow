import Foundation

public enum RecordedLowLevelEventKind: Hashable, Sendable {
    case mouseDown(button: MouseButton, location: ScreenPoint)
    case mouseDrag(button: MouseButton, startLocation: ScreenPoint, endLocation: ScreenPoint)
    case scroll(location: ScreenPoint, deltaX: Int, deltaY: Int)
    case keyDown(keyCode: String, modifiers: [String], bundleID: String?, holdDurationMs: Int?)
}

public struct RecordedLowLevelEvent: Hashable, Sendable {
    public var timestamp: TimeInterval
    public var kind: RecordedLowLevelEventKind

    public init(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime, kind: RecordedLowLevelEventKind) {
        self.timestamp = timestamp
        self.kind = kind
    }
}

public struct RecorderPipelineConfiguration: Hashable, Sendable {
    public var idleWaitThresholdMs: Int
    public var minimumWaitMs: Int

    public init(idleWaitThresholdMs: Int = 120, minimumWaitMs: Int = 120) {
        self.idleWaitThresholdMs = max(0, idleWaitThresholdMs)
        self.minimumWaitMs = max(0, minimumWaitMs)
    }
}

public struct RecorderSemanticPipeline: Sendable {
    private let targetHint: TargetHint
    private let configuration: RecorderPipelineConfiguration
    private var lastAcceptedEventAt: TimeInterval?

    public init(
        targetHint: TargetHint,
        configuration: RecorderPipelineConfiguration = RecorderPipelineConfiguration()
    ) {
        self.targetHint = targetHint
        self.configuration = configuration
    }

    public mutating func consume(
        _ event: RecordedLowLevelEvent,
        in window: BoundWindow?
    ) -> [FlowStep] {
        guard let semanticEvent = semanticEvent(for: event, in: window) else {
            return []
        }

        var emittedSteps: [FlowStep] = []

        if let lastAcceptedEventAt {
            let gapMs = Int(((event.timestamp - lastAcceptedEventAt) * 1000).rounded())
            if gapMs >= configuration.idleWaitThresholdMs {
                emittedSteps.append(
                    FlowStep.wait(
                        ordinal: emittedSteps.count,
                        durationMs: max(configuration.minimumWaitMs, gapMs)
                    )
                )
            }
        }

        emittedSteps.append(semanticEvent)
        emittedSteps = emittedSteps.enumerated().map { index, step in
            var mutableStep = step
            mutableStep.ordinal = index
            return mutableStep
        }

        lastAcceptedEventAt = event.timestamp
        return emittedSteps
    }

    private func semanticEvent(
        for event: RecordedLowLevelEvent,
        in window: BoundWindow?
    ) -> FlowStep? {
        switch event.kind {
        case .mouseDown(let button, let location):
            guard let window else { return nil }
            guard window.geometry.contentRect.contains(location) else { return nil }
            let point = normalizedPoint(for: location, in: window.geometry.contentRect, clampToBounds: false)
            return FlowStep.clickAt(ordinal: 0, point: point, button: button)

        case .mouseDrag(let button, let startLocation, let endLocation):
            guard let window else { return nil }
            guard window.geometry.contentRect.contains(startLocation) else { return nil }
            let startPoint = normalizedPoint(for: startLocation, in: window.geometry.contentRect, clampToBounds: false)
            let endPoint = normalizedPoint(for: endLocation, in: window.geometry.contentRect, clampToBounds: true)
            return FlowStep.dragTo(ordinal: 0, from: startPoint, to: endPoint, button: button)

        case .scroll(let location, let deltaX, let deltaY):
            guard let window else { return nil }
            guard window.geometry.contentRect.contains(location) else { return nil }
            guard deltaX != 0 || deltaY != 0 else { return nil }
            let point = normalizedPoint(for: location, in: window.geometry.contentRect, clampToBounds: false)
            return FlowStep.scrollAt(ordinal: 0, point: point, deltaX: deltaX, deltaY: deltaY)

        case .keyDown(let keyCode, let modifiers, let bundleID, let holdDurationMs):
            guard !Self.isModifierOnlyKey(keyCode) else { return nil }

            if let expectedBundleID = window?.descriptor.bundleID ?? targetHint.bundleID,
               let bundleID,
               expectedBundleID != bundleID {
                return nil
            }

            return FlowStep.pressKey(
                ordinal: 0,
                keyCode: keyCode,
                modifiers: modifiers,
                durationMs: isHoldDurationRecorderKey(keyCode) ? holdDurationMs : nil
            )
        }
    }

    public static func isModifierOnlyRecorderKey(_ keyCode: String) -> Bool {
        switch keyCode.uppercased() {
        case "KEY_54", "KEY_55", "KEY_56", "KEY_57", "KEY_58", "KEY_59", "KEY_60", "KEY_61", "KEY_62", "KEY_63":
            return true
        default:
            return false
        }
    }

    private static func isModifierOnlyKey(_ keyCode: String) -> Bool {
        isModifierOnlyRecorderKey(keyCode)
    }

    private func isHoldDurationRecorderKey(_ keyCode: String) -> Bool {
        switch keyCode.uppercased() {
        case "LEFT", "RIGHT", "UP", "DOWN":
            return true
        default:
            return false
        }
    }

    private func normalizedPoint(for location: ScreenPoint, in rect: ScreenRect, clampToBounds: Bool) -> NormalizedPoint {
        let normalizedX = (location.x - rect.x) / rect.width
        let normalizedY = (location.y - rect.y) / rect.height

        if !clampToBounds {
            return NormalizedPoint(x: normalizedX, y: normalizedY)
        }

        return NormalizedPoint(
            x: min(1, max(0, normalizedX)),
            y: min(1, max(0, normalizedY))
        )
    }
}
