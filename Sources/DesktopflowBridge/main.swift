import AppKit
import ApplicationServices
import DesktopflowCore
import DesktopflowPlatform
import DesktopflowStorage
import Dispatch
import Foundation

enum BridgeError: LocalizedError {
    case usage(String)
    case invalidUUID(String)
    case flowNotFound(UUID)
    case invalidTargetHint(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .invalidUUID(let rawValue):
            return "Invalid UUID: \(rawValue)"
        case .flowNotFound(let id):
            return "Flow not found: \(id.uuidString)"
        case .invalidTargetHint(let reason):
            return "Invalid target hint: \(reason)"
        }
    }
}

struct PermissionSnapshot: Codable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var screenRecording: Bool
}

struct RecorderEventEnvelope: Codable {
    var type: String
    var message: String?
    var count: Int?
    var step: FlowStep?
    var steps: [FlowStep]?
}

enum RecorderSessionError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "Desktopflow could not install a macOS input event tap. Check Input Monitoring permission and restart the app."
        }
    }
}

@main
struct DesktopflowBridge {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                throw BridgeError.usage("Usage: DesktopflowBridge <list-windows|permissions|run-flow|record> ...")
            }

            switch command {
            case "list-windows":
                try writeJSON(SystemWindowCatalog().listWindowsSync())
            case "permissions":
                try writeJSON(currentPermissions())
            case "run-flow":
                try runFlowSync(arguments: Array(arguments.dropFirst()))
            case "record":
                try runRecorder(arguments: Array(arguments.dropFirst()))
            default:
                throw BridgeError.usage("Unknown command: \(command)")
            }
        } catch {
            writeErrorAndExit(error)
        }
    }

    private static func runFlow(arguments: [String]) async throws {
        guard arguments.count >= 2 else {
            throw BridgeError.usage("Usage: DesktopflowBridge run-flow <workspace-root> <flow-id>")
        }

        let workspaceRoot = arguments[0]
        guard let flowID = UUID(uuidString: arguments[1]) else {
            throw BridgeError.invalidUUID(arguments[1])
        }

        let flowRepository = FileFlowRepository(directoryURL: BridgeWorkspacePaths.flowsDirectory(rootPath: workspaceRoot))
        let anchorRepository = FileAnchorRepository(directoryURL: BridgeWorkspacePaths.anchorsDirectory(rootPath: workspaceRoot))

        guard let flow = try await flowRepository.loadFlow(id: flowID) else {
            throw BridgeError.flowNotFound(flowID)
        }

        let anchors = try await anchorRepository.listAnchors()
        let report = await FlowRunner(
            windowBinder: SystemWindowCatalog(),
            frameProvider: PlaceholderFrameProvider(),
            matcher: PlaceholderTemplateMatcher(),
            inputDispatcher: CoreGraphicsInputDispatcher()
        ).run(
            FlowRunRequest(
                flow: flow,
                anchorsByID: Dictionary(uniqueKeysWithValues: anchors.map { ($0.id, $0) })
            ),
            control: RunControl()
        )

        try writeJSON(report)
    }

    private static func runFlowSync(arguments: [String]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = LockedBox<Error>()

        Task {
            do {
                try await runFlow(arguments: arguments)
            } catch {
                errorBox.value = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = errorBox.value {
            throw error
        }
    }

    private static func runRecorder(arguments: [String]) throws {
        guard let targetHintJSON = arguments.first else {
            throw BridgeError.usage("Usage: DesktopflowBridge record '<target-hint-json>'")
        }

        let data = Data(targetHintJSON.utf8)
        let targetHint = try makeDecoder().decode(TargetHint.self, from: data)
        let sessionBox = LockedBox<RecorderSession>()
        let errorBox = LockedBox<Error>()
        let completionBox = LockedBox<Bool>()
        completionBox.value = false

        Task { @MainActor in
            do {
                let application = NSApplication.shared
                application.setActivationPolicy(.accessory)
                let session = RecorderSession(targetHint: targetHint)
                try session.start()
                sessionBox.value = session
            } catch {
                errorBox.value = error
            }
            completionBox.value = true
        }

        while completionBox.value != true {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        if let error = errorBox.value {
            throw error
        }

        guard let session = sessionBox.value else {
            throw BridgeError.invalidTargetHint("Recorder session could not be created.")
        }

        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData

            if data.isEmpty {
                FileHandle.standardInput.readabilityHandler = nil
                Task { @MainActor in
                    session.stop()
                }
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            if text
                .split(whereSeparator: \.isNewline)
                .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop" }) {
                FileHandle.standardInput.readabilityHandler = nil
                Task { @MainActor in
                    session.stop()
                }
            }
        }

        RunLoop.main.run()
    }
    static func currentPermissions() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func writeJSON<T: Encodable>(_ value: T) throws {
        let data = try makeEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    static func writeRecorderEvent(_ event: RecorderEventEnvelope) {
        do {
            try writeJSON(event)
        } catch {
            writeErrorAndExit(error)
        }
    }

    static func writeErrorAndExit(_ error: Error) -> Never {
        let message = error.localizedDescription
        if let data = try? makeEncoder().encode(["error": message]) {
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data([0x0A]))
        } else {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
        }
        Foundation.exit(1)
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

enum BridgeWorkspacePaths {
    static func root(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    static func flowsDirectory(rootPath: String) -> URL {
        root(rootPath: rootPath).appending(path: "flows")
    }

    static func anchorsDirectory(rootPath: String) -> URL {
        root(rootPath: rootPath).appending(path: "anchors")
    }
}

@MainActor
final class RecorderSession {
    private let targetHint: TargetHint
    private let windowCatalog = SystemWindowCatalog()
    private var recordingWindow: BoundWindow?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private(set) var recordedSteps: [FlowStep] = []
    private var isRecording = false
    private var pipeline: RecorderSemanticPipeline
    private var rawEventCount = 0
    private var rawMouseEventCount = 0
    private var rawKeyEventCount = 0
    private var droppedMouseOutsideWindowCount = 0
    private var droppedKeyWrongAppCount = 0
    private var droppedModifierOnlyKeyCount = 0

    init(targetHint: TargetHint) {
        self.targetHint = targetHint
        self.pipeline = RecorderSemanticPipeline(targetHint: targetHint)
    }

    func start() throws {
        recordingWindow = try windowCatalog.resolveWindowSync(using: targetHint)
        try installEventTap()
        isRecording = true
        DesktopflowBridge.writeRecorderEvent(RecorderEventEnvelope(type: "ready"))
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        removeEventTap()
        FileHandle.standardInput.readabilityHandler = nil
        DesktopflowBridge.writeRecorderEvent(
            RecorderEventEnvelope(
                type: "stopped",
                message: stopMessage(),
                count: recordedSteps.count,
                steps: recordedSteps
            )
        )
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func installEventTap() throws {
        let mask = eventMask(for: .leftMouseDown) | eventMask(for: .rightMouseDown) | eventMask(for: .keyDown)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let session = Unmanaged<RecorderSession>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                await session.handleRecordedEvent(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw RecorderSessionError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw RecorderSessionError.eventTapUnavailable
        }

        self.eventTap = eventTap
        self.eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func removeEventTap() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }

    private func handleRecordedEvent(type: CGEventType, event: CGEvent) async {
        guard isRecording else { return }
        rawEventCount += 1
        let eventTimestamp = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime

        if let latestWindow = try? await windowCatalog.attach(using: targetHint) {
            recordingWindow = latestWindow
        }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .leftMouseDown, .rightMouseDown:
            rawMouseEventCount += 1
            recordEvent(
                RecordedLowLevelEvent(
                    timestamp: eventTimestamp,
                    kind: .mouseDown(
                        button: type == .rightMouseDown ? .right : .left,
                        location: ScreenPoint(
                            x: event.location.x,
                            y: event.location.y
                        )
                    )
                )
            )
        case .keyDown:
            rawKeyEventCount += 1
            recordEvent(
                RecordedLowLevelEvent(
                    timestamp: eventTimestamp,
                    kind: .keyDown(
                        keyCode: keyIdentifier(for: event),
                        modifiers: modifiers(for: event),
                        bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    )
                )
            )
        default:
            break
        }
    }

    private func recordEvent(_ event: RecordedLowLevelEvent) {
        switch event.kind {
        case .mouseDown(_, let location):
            guard let recordingWindow else { return }
            guard recordingWindow.geometry.contentRect.contains(location) else {
                droppedMouseOutsideWindowCount += 1
                return
            }
        case .keyDown(let keyCode, _, let bundleID):
            if RecorderSemanticPipeline.isModifierOnlyRecorderKey(keyCode) {
                droppedModifierOnlyKeyCount += 1
                return
            }

            if let expectedBundleID = recordingWindow?.descriptor.bundleID ?? targetHint.bundleID,
               let bundleID,
               expectedBundleID != bundleID {
                droppedKeyWrongAppCount += 1
                return
            }
        }

        let newSteps = pipeline.consume(event, in: recordingWindow)
        guard !newSteps.isEmpty else { return }

        for step in newSteps {
            var emittedStep = step
            emittedStep.ordinal = recordedSteps.count
            recordedSteps.append(emittedStep)
            DesktopflowBridge.writeRecorderEvent(
                RecorderEventEnvelope(
                    type: "stepCaptured",
                    message: "Captured \(recordedSteps.count) step\(recordedSteps.count == 1 ? "" : "s").",
                    count: recordedSteps.count,
                    step: emittedStep
                )
            )
        }
    }

    private func stopMessage() -> String {
        guard recordedSteps.isEmpty else {
            return "Recording stopped with \(recordedSteps.count) captured steps."
        }

        if rawEventCount == 0 {
            let permissions = DesktopflowBridge.currentPermissions()
            if !permissions.accessibility || !permissions.inputMonitoring {
                return "Recording stopped with no captured steps. The bridge saw 0 input events; grant Accessibility and Input Monitoring in macOS Settings."
            }
            return "Recording stopped with no captured steps. The bridge saw 0 input events from macOS."
        }

        if droppedMouseOutsideWindowCount > 0 && rawMouseEventCount == droppedMouseOutsideWindowCount && rawKeyEventCount == 0 {
            return "Recording stopped with no captured steps. Mouse events were seen, but they landed outside the selected target window."
        }

        if droppedKeyWrongAppCount > 0 && rawKeyEventCount == droppedKeyWrongAppCount && rawMouseEventCount == 0 {
            return "Recording stopped with no captured steps. Key events were seen, but the selected target app was not frontmost."
        }

        if droppedModifierOnlyKeyCount > 0 && rawKeyEventCount == droppedModifierOnlyKeyCount && rawMouseEventCount == 0 {
            return "Recording stopped with no captured steps. Only modifier keys were pressed."
        }

        return "Recording stopped with no captured steps. Raw events were seen, but none matched the selected target window/app filters."
    }

    private func keyIdentifier(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36:
            return "RETURN"
        case 48:
            return "TAB"
        case 49:
            return "SPACE"
        case 51:
            return "DELETE"
        case 53:
            return "ESCAPE"
        case 123:
            return "LEFT"
        case 124:
            return "RIGHT"
        case 125:
            return "DOWN"
        case 126:
            return "UP"
        default:
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return characters?.isEmpty == false ? characters! : "KEY_\(event.keyCode)"
        }
    }

    private func keyIdentifier(for event: CGEvent) -> String {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case 36:
            return "RETURN"
        case 48:
            return "TAB"
        case 49:
            return "SPACE"
        case 51:
            return "DELETE"
        case 53:
            return "ESCAPE"
        case 123:
            return "LEFT"
        case 124:
            return "RIGHT"
        case 125:
            return "DOWN"
        case 126:
            return "UP"
        default:
            if let unicodeString = event.readUnicodeString(),
               !unicodeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return unicodeString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
            return "KEY_\(keyCode)"
        }
    }

    private func modifiers(for event: CGEvent) -> [String] {
        let flags = event.flags
        var modifiers: [String] = []
        if flags.contains(.maskCommand) { modifiers.append("command") }
        if flags.contains(.maskAlternate) { modifiers.append("option") }
        if flags.contains(.maskControl) { modifiers.append("control") }
        if flags.contains(.maskShift) { modifiers.append("shift") }
        if flags.contains(.maskAlphaShift) { modifiers.append("capsLock") }
        return modifiers
    }
}

private extension CGEvent {
    func readUnicodeString() -> String? {
        var length: Int = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }

        let buffer = UnsafeMutablePointer<UniChar>.allocate(capacity: length)
        defer { buffer.deallocate() }

        var actualLength: Int = 0
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &actualLength, unicodeString: buffer)
        guard actualLength > 0 else { return nil }

        return String(utf16CodeUnits: buffer, count: actualLength)
    }
}

private extension NSEvent {
    var timestampDate: Date {
        Date(timeIntervalSinceReferenceDate: timestamp)
    }
}
