import AppKit
import DesktopflowCore
import DesktopflowPlatform
import DesktopflowStorage
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var flows: [Flow] = []
    @Published var anchors: [Anchor] = []
    @Published var selectedFlowID: UUID?
    @Published var lastError: String?
    @Published var availableWindows: [WindowDescriptor] = []
    @Published var selectedWindowID: UUID?
    @Published var recordedSteps: [FlowStep] = []
    @Published var isRecording = false
    @Published var recorderStatus = "Idle"
    @Published var recorderFlowName = "Recorded Flow"
    @Published var isRunningFlow = false
    @Published var runnerStatus = "Idle"
    @Published var lastRunReport: FlowRunReport?

    private let flowRepository: any FlowRepository
    private let anchorRepository: any AnchorRepository
    private let windowCatalog = SystemWindowCatalog()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var recordingTargetHint: TargetHint?
    private var recordingWindow: BoundWindow?
    private var runControl: RunControl?

    init(flowRepository: any FlowRepository, anchorRepository: any AnchorRepository) {
        self.flowRepository = flowRepository
        self.anchorRepository = anchorRepository
    }

    var selectedFlow: Flow? {
        flows.first(where: { $0.id == selectedFlowID }) ?? flows.first
    }

    var selectedWindow: WindowDescriptor? {
        availableWindows.first(where: { $0.id == selectedWindowID }) ?? availableWindows.first
    }

    func load() async {
        do {
            try await seedIfNeeded()
            flows = try await flowRepository.listFlows()
            anchors = try await anchorRepository.listAnchors()
            selectedFlowID = selectedFlowID ?? flows.first?.id
            try await refreshWindows()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshWindows() async throws {
        let windows = try await windowCatalog.listWindows()
        availableWindows = windows
        if let selectedWindowID, windows.contains(where: { $0.id == selectedWindowID }) {
            return
        }
        selectedWindowID = windows.first?.id
    }

    func startRecording() async {
        guard !isRecording else { return }
        guard let selectedWindow else {
            recorderStatus = "Choose a target window first."
            return
        }

        do {
            let hint = targetHint(for: selectedWindow)
            recordingTargetHint = hint
            recordingWindow = try await windowCatalog.attach(using: hint)
            recordedSteps = []
            recorderStatus = "Recording \(selectedWindow.appName) / \(selectedWindow.title)"
            isRecording = true
            installEventMonitors()
        } catch {
            recorderStatus = error.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        removeEventMonitors()
        isRecording = false
        recorderStatus = recordedSteps.isEmpty ? "Recording stopped with no captured steps." : "Recording stopped with \(recordedSteps.count) captured steps."
    }

    func saveRecording() async {
        guard !recordedSteps.isEmpty else {
            recorderStatus = "Record at least one click or key press before saving."
            return
        }
        guard let selectedWindow else {
            recorderStatus = "Target window is missing."
            return
        }

        stopRecording()

        let name = recorderFlowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recorded Flow" : recorderFlowName.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = [
            FlowStep.attachWindow(ordinal: 0),
            FlowStep.focusWindow(ordinal: 1)
        ] + recordedSteps.enumerated().map { index, step in
            var mutableStep = step
            mutableStep.ordinal = index + 2
            return mutableStep
        }

        let flow = Flow(
            name: name,
            description: "Recorded from \(selectedWindow.appName) / \(selectedWindow.title)",
            targetHint: targetHint(for: selectedWindow),
            steps: steps
        )

        do {
            try await flowRepository.saveFlow(flow)
            selectedFlowID = flow.id
            recorderStatus = "Saved \(steps.count - 2) recorded steps to '\(flow.name)'."
            await load()
            selectedFlowID = flow.id
        } catch {
            recorderStatus = error.localizedDescription
        }
    }

    func runSelectedFlow() async {
        guard !isRunningFlow else { return }
        guard let flow = selectedFlow else {
            runnerStatus = "Select a flow first."
            return
        }

        if flowRequiresVision(flow) {
            runnerStatus = "This flow uses visual anchors. Anchor-based playback is not wired yet."
            return
        }

        let control = RunControl()
        runControl = control
        isRunningFlow = true
        runnerStatus = "Running '\(flow.name)'..."
        lastRunReport = nil

        let runner = FlowRunner(
            windowBinder: windowCatalog,
            frameProvider: PlaceholderFrameProvider(),
            matcher: PlaceholderTemplateMatcher(),
            inputDispatcher: CoreGraphicsInputDispatcher()
        )
        let anchorsByID = Dictionary(uniqueKeysWithValues: anchors.map { ($0.id, $0) })
        let report = await runner.run(FlowRunRequest(flow: flow, anchorsByID: anchorsByID), control: control)

        lastRunReport = report
        isRunningFlow = false
        runControl = nil

        switch report.status {
        case .succeeded:
            runnerStatus = "Playback finished successfully."
        case .aborted:
            runnerStatus = "Playback aborted."
        default:
            runnerStatus = report.stopReason ?? "Playback failed."
        }
    }

    func abortRunningFlow() async {
        await runControl?.abort()
    }

    private func seedIfNeeded() async throws {
        let existingFlows = try await flowRepository.listFlows()
        guard existingFlows.isEmpty else { return }
        try await flowRepository.saveFlow(SampleData.practiceFlow)
        try await anchorRepository.saveAnchor(SampleData.inventoryAnchor)
    }

    private func installEventMonitors() {
        removeEventMonitors()

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
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleRecordedEvent(_ event: NSEvent) async {
        guard isRecording, let recordingTargetHint else { return }

        if let latestWindow = try? await windowCatalog.attach(using: recordingTargetHint) {
            recordingWindow = latestWindow
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            await recordMouseEvent(event)
        case .keyDown:
            recordKeyEvent(event)
        default:
            break
        }
    }

    private func recordMouseEvent(_ event: NSEvent) async {
        guard let recordingWindow else { return }

        let location = event.cgEvent?.location ?? NSEvent.mouseLocation
        let point = ScreenPoint(x: location.x, y: location.y)
        guard recordingWindow.geometry.contentRect.contains(point) else { return }

        let rect = recordingWindow.geometry.contentRect
        let normalizedPoint = NormalizedPoint(
            x: (point.x - rect.x) / rect.width,
            y: (point.y - rect.y) / rect.height
        )
        let button: MouseButton = event.type == .rightMouseDown ? .right : .left
        let step = FlowStep.clickAt(ordinal: recordedSteps.count, point: normalizedPoint, button: button)
        recordedSteps.append(step)
        recorderStatus = "Captured \(recordedSteps.count) step\(recordedSteps.count == 1 ? "" : "s")."
    }

    private func recordKeyEvent(_ event: NSEvent) {
        guard let selectedWindow else { return }

        if let bundleID = selectedWindow.bundleID,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID {
            return
        }

        let step = FlowStep.pressKey(
            ordinal: recordedSteps.count,
            keyCode: keyIdentifier(for: event),
            modifiers: modifiers(for: event)
        )
        recordedSteps.append(step)
        recorderStatus = "Captured \(recordedSteps.count) step\(recordedSteps.count == 1 ? "" : "s")."
    }

    private func targetHint(for window: WindowDescriptor) -> TargetHint {
        TargetHint(
            bundleID: window.bundleID,
            appName: window.appName,
            windowTitleContains: window.title,
            ownerPID: window.ownerPID
        )
    }

    private func flowRequiresVision(_ flow: Flow) -> Bool {
        flow.steps.contains(where: { $0.type == .waitForAnchor || !$0.preconditions.isEmpty || !$0.postconditions.isEmpty })
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
