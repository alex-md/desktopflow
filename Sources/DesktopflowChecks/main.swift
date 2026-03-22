import DesktopflowCore
import Foundation

@main
struct DesktopflowChecks {
    static func main() async {
        do {
            try coordinateMappingCheck()
            try flowSerializationCheck()
            try recorderPipelineCheck()
            try recorderDefaultWaitSensitivityCheck()
            try await runnerCheck()
            try await runnerConditionPollingCheck()
            print("DesktopflowChecks: all checks passed.")
        } catch {
            fputs("DesktopflowChecks failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func coordinateMappingCheck() throws {
        let geometry = WindowGeometry(
            frameRect: ScreenRect(x: 100, y: 100, width: 1024, height: 768),
            contentRect: ScreenRect(x: 112, y: 144, width: 1000, height: 700)
        )
        let point = geometry.screenPoint(for: NormalizedPoint(x: 0.5, y: 0.25))
        try expect(abs(point.x - 612) < 0.001, "Coordinate mapping should target the content rect.")
        try expect(abs(point.y - 319) < 0.001, "Coordinate mapping should preserve normalized y.")
    }

    private static func flowSerializationCheck() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(SampleData.practiceFlow)
        let decoded = try decoder.decode(Flow.self, from: data)

        try expect(decoded.steps.count == 6, "Sample flow should round-trip with all semantic steps intact.")
        try expect(decoded.steps[2].type == .waitForAnchor, "Anchor wait step should survive serialization.")
    }

    private static func recorderPipelineCheck() throws {
        let window = BoundWindow(
            descriptor: WindowDescriptor(bundleID: "com.example.Target", appName: "Target", title: "Arena"),
            geometry: WindowGeometry(
                frameRect: ScreenRect(x: 100, y: 100, width: 1024, height: 768),
                contentRect: ScreenRect(x: 120, y: 140, width: 900, height: 620)
            )
        )

        var pipeline = RecorderSemanticPipeline(
            targetHint: TargetHint(bundleID: "com.example.Target"),
            configuration: RecorderPipelineConfiguration(idleWaitThresholdMs: 350, minimumWaitMs: 250)
        )

        let start: TimeInterval = 10_000
        let first = pipeline.consume(
            RecordedLowLevelEvent(
                timestamp: start,
                kind: .mouseDown(button: .left, location: ScreenPoint(x: 570, y: 450))
            ),
            in: window
        )
        let second = pipeline.consume(
            RecordedLowLevelEvent(
                timestamp: start + 1.4,
                kind: .keyDown(keyCode: "SPACE", modifiers: [], bundleID: "com.example.Target")
            ),
            in: window
        )
        let third = pipeline.consume(
            RecordedLowLevelEvent(
                timestamp: start + 1.8,
                kind: .mouseDown(button: .left, location: ScreenPoint(x: 600, y: 470))
            ),
            in: window
        )

        try expect(first.count == 1, "First accepted low-level event should produce one semantic step.")
        try expect(first.first?.type == .clickAt, "Mouse down should become a click semantic step.")
        try expect(second.count == 2, "Recorder pipeline should inject a wait step before a delayed action.")
        try expect(second.first?.type == .wait, "Recorder pipeline should emit a wait step after an idle gap.")
        try expect(second.last?.type == .pressKey, "Key down should become a pressKey semantic step.")
        try expect(second.first?.params.durationMs == 1_400, "Wait duration should preserve the observed idle gap.")
        try expect(third.count == 2, "Consecutive clicks with a short pause should still capture an explicit wait.")
        try expect(third.first?.type == .wait, "Short click pauses should become wait steps.")
        try expect(third.first?.params.durationMs == 400, "Short click waits should preserve the observed pause.")
        try expect(third.last?.type == .clickAt, "The click after a short pause should still be recorded.")
    }

    private static func recorderDefaultWaitSensitivityCheck() throws {
        let window = BoundWindow(
            descriptor: WindowDescriptor(bundleID: "com.example.Target", appName: "Target", title: "Arena"),
            geometry: WindowGeometry(
                frameRect: ScreenRect(x: 100, y: 100, width: 1024, height: 768),
                contentRect: ScreenRect(x: 120, y: 140, width: 900, height: 620)
            )
        )

        var pipeline = RecorderSemanticPipeline(targetHint: TargetHint(bundleID: "com.example.Target"))
        let start: TimeInterval = 20_000

        _ = pipeline.consume(
            RecordedLowLevelEvent(
                timestamp: start,
                kind: .mouseDown(button: .left, location: ScreenPoint(x: 570, y: 450))
            ),
            in: window
        )
        let second = pipeline.consume(
            RecordedLowLevelEvent(
                timestamp: start + 0.2,
                kind: .mouseDown(button: .left, location: ScreenPoint(x: 600, y: 470))
            ),
            in: window
        )

        try expect(second.count == 2, "Default recorder settings should capture brief human pauses between clicks.")
        try expect(second.first?.type == .wait, "Default recorder settings should emit a wait step for brief pauses.")
        try expect(second.first?.params.durationMs == 200, "Default recorder waits should preserve the observed pause length.")
        try expect(second.last?.type == .clickAt, "The delayed click should still be recorded after the wait step.")
    }

    private static func runnerCheck() async throws {
        let window = BoundWindow(
            descriptor: WindowDescriptor(appName: "Practice", title: "Arena"),
            geometry: WindowGeometry(
                frameRect: ScreenRect(x: 200, y: 100, width: 900, height: 700),
                contentRect: ScreenRect(x: 220, y: 140, width: 860, height: 620)
            )
        )

        let runner = FlowRunner(
            windowBinder: CheckWindowBinder(window: window),
            frameProvider: CheckFrameProvider(),
            matcher: CheckTemplateMatcher(successOnAttempt: 3),
            inputDispatcher: CheckInputDispatcher(),
            diagnostics: NullDiagnosticsSink(),
            sleeper: CheckSleeper()
        )

        let control = RunControl()
        let report = await runner.run(
            FlowRunRequest(
                flow: SampleData.practiceFlow,
                anchorsByID: [SampleData.inventoryAnchor.id: SampleData.inventoryAnchor]
            ),
            control: control
        )

        try expect(report.status == .succeeded, "Runner should complete the sample flow.")
        try expect(report.stepResults.count == 6, "Runner should record each step result.")
    }

    private static func runnerConditionPollingCheck() async throws {
        let window = BoundWindow(
            descriptor: WindowDescriptor(appName: "Practice", title: "Arena"),
            geometry: WindowGeometry(
                frameRect: ScreenRect(x: 200, y: 100, width: 900, height: 700),
                contentRect: ScreenRect(x: 220, y: 140, width: 860, height: 620)
            )
        )

        var clickWithPostcondition = FlowStep.clickAt(ordinal: 1, point: NormalizedPoint(x: 0.5, y: 0.5))
        clickWithPostcondition.postconditions = [StepCondition(anchorID: SampleData.inventoryAnchor.id, expectedVisible: true)]
        clickWithPostcondition.timeoutMs = 1_000
        clickWithPostcondition.params.pollIntervalMs = 10

        let flow = Flow(
            name: "Condition Polling",
            description: "Verify that postconditions poll until matched.",
            targetHint: TargetHint(appName: "Practice", windowTitleContains: "Arena"),
            defaultTimeoutMs: 1_000,
            steps: [
                .attachWindow(ordinal: 0),
                clickWithPostcondition
            ]
        )

        let runner = FlowRunner(
            windowBinder: CheckWindowBinder(window: window),
            frameProvider: CheckFrameProvider(),
            matcher: CheckTemplateMatcher(successOnAttempt: 3),
            inputDispatcher: CheckInputDispatcher(),
            diagnostics: NullDiagnosticsSink(),
            sleeper: CheckSleeper()
        )

        let report = await runner.run(
            FlowRunRequest(
                flow: flow,
                anchorsByID: [SampleData.inventoryAnchor.id: SampleData.inventoryAnchor]
            ),
            control: RunControl()
        )

        try expect(report.status == .succeeded, "Runner should poll postconditions until they match.")
        try expect(report.stepResults.count == 2, "Runner should preserve both step results when polling conditions.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckError(message)
        }
    }
}

private struct CheckError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private actor CheckWindowBinder: WindowBinder {
    let window: BoundWindow

    init(window: BoundWindow) {
        self.window = window
    }

    func attach(using hint: TargetHint) async throws -> BoundWindow {
        window
    }
}

private actor CheckFrameProvider: FrameProvider {
    func captureFrame(for window: BoundWindow) async throws -> CapturedFrame {
        CapturedFrame(windowID: window.descriptor.id, imageData: Data([0x01]), pixelSize: ScreenSize(width: 800, height: 600))
    }
}

private actor CheckTemplateMatcher: TemplateMatcher {
    let successOnAttempt: Int
    private var attempts = 0

    init(successOnAttempt: Int) {
        self.successOnAttempt = successOnAttempt
    }

    func match(anchor: Anchor, within frame: CapturedFrame) async throws -> AnchorMatch {
        attempts += 1
        return AnchorMatch(confidence: attempts >= successOnAttempt ? 0.95 : 0.4, matchedRegion: anchor.region)
    }
}

private actor CheckInputDispatcher: InputDispatcher {
    func focus(window: BoundWindow) async throws {}
    func click(at point: ScreenPoint, button: MouseButton) async throws {}
    func pressKey(keyCode: String, modifiers: [String]) async throws {}
}

private actor CheckSleeper: Sleeper {
    func sleep(milliseconds: Int) async throws {}
}
