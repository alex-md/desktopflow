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
    private let source: CGEventSource?

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
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType

        switch button {
        case .left:
            mouseButton = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        case .right:
            mouseButton = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case .center:
            mouseButton = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        }

        try postMouseEvent(type: .mouseMoved, location: location, button: mouseButton)
        try await Task.sleep(for: .milliseconds(25))
        try postMouseEvent(type: downType, location: location, button: mouseButton)
        try postMouseEvent(type: upType, location: location, button: mouseButton)
    }

    public func pressKey(keyCode: String, modifiers: [String]) async throws {
        let resolvedKeyCode = try Self.resolveKeyCode(keyCode)
        let flags = Self.resolveModifierFlags(modifiers)

        let downEvent = try makeKeyEvent(keyCode: resolvedKeyCode, keyDown: true, flags: flags)
        let upEvent = try makeKeyEvent(keyCode: resolvedKeyCode, keyDown: false, flags: flags)
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
    }

    private func postMouseEvent(type: CGEventType, location: CGPoint, button: CGMouseButton) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
            throw CoreGraphicsInputError.eventCreationFailed("mouse")
        }
        event.post(tap: .cghidEventTap)
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
