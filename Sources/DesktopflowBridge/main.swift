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
        let semaphore = DispatchSemaphore(value: 0)
        let sessionBox = LockedBox<RecorderSession>()
        let errorBox = LockedBox<Error>()

        Task { @MainActor in
            do {
                let session = RecorderSession(targetHint: targetHint)
                try await session.start()
                sessionBox.value = session
            } catch {
                errorBox.value = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = errorBox.value {
            throw error
        }

        guard let session = sessionBox.value else {
            throw BridgeError.invalidTargetHint("Recorder session could not be created.")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine(strippingNewline: true) {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop" {
                    Task { @MainActor in
                        session.stop()
                    }
                    return
                }
            }

            Task { @MainActor in
                session.stop()
            }
        }

        RunLoop.main.run()
    }
    private static func currentPermissions() -> PermissionSnapshot {
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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var recordedSteps: [FlowStep] = []
    private var isRecording = false
    private var pipeline: RecorderSemanticPipeline

    init(targetHint: TargetHint) {
        self.targetHint = targetHint
        self.pipeline = RecorderSemanticPipeline(targetHint: targetHint)
    }

    func start() async throws {
        recordingWindow = try await windowCatalog.attach(using: targetHint)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.handleRecordedEvent(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.handleRecordedEvent(event)
            }
            return event
        }
        isRecording = true
        DesktopflowBridge.writeRecorderEvent(RecorderEventEnvelope(type: "ready"))
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        DesktopflowBridge.writeRecorderEvent(
            RecorderEventEnvelope(
                type: "stopped",
                message: recordedSteps.isEmpty ? "Recording stopped with no captured steps." : "Recording stopped with \(recordedSteps.count) captured steps.",
                count: recordedSteps.count,
                steps: recordedSteps
            )
        )
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func handleRecordedEvent(_ event: NSEvent) async {
        guard isRecording else { return }

        if let latestWindow = try? await windowCatalog.attach(using: targetHint) {
            recordingWindow = latestWindow
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            recordEvent(
                RecordedLowLevelEvent(
                    timestamp: event.timestampDate,
                    kind: .mouseDown(
                        button: event.type == .rightMouseDown ? .right : .left,
                        location: ScreenPoint(
                            x: (event.cgEvent?.location ?? NSEvent.mouseLocation).x,
                            y: (event.cgEvent?.location ?? NSEvent.mouseLocation).y
                        )
                    )
                )
            )
        case .keyDown:
            recordEvent(
                RecordedLowLevelEvent(
                    timestamp: event.timestampDate,
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

    private func modifiers(for event: NSEvent) -> [String] {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [String] = []
        if flags.contains(.command) { modifiers.append("command") }
        if flags.contains(.option) { modifiers.append("option") }
        if flags.contains(.control) { modifiers.append("control") }
        if flags.contains(.shift) { modifiers.append("shift") }
        if flags.contains(.capsLock) { modifiers.append("capsLock") }
        return modifiers
    }
}

private extension NSEvent {
    var timestampDate: Date {
        Date(timeIntervalSinceReferenceDate: timestamp)
    }
}
