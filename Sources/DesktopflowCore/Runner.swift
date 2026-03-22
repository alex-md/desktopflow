import Foundation

public enum FlowRunnerError: LocalizedError, Equatable, Sendable {
    case missingWindow
    case missingAnchor(UUID)
    case invalidStepParameters(String)
    case timeout(String)
    case aborted

    public var errorDescription: String? {
        switch self {
        case .missingWindow:
            return "The target window is not attached."
        case .missingAnchor(let id):
            return "Missing anchor for id \(id.uuidString)."
        case .invalidStepParameters(let details):
            return "Invalid step parameters: \(details)"
        case .timeout(let details):
            return "Timed out: \(details)"
        case .aborted:
            return "Run aborted."
        }
    }
}

public actor RunControl {
    private var isPaused = false
    private var abortRequested = false

    public init() {}

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }

    public func abort() {
        abortRequested = true
        isPaused = false
    }

    public func checkpoint() async throws {
        while isPaused && !abortRequested {
            try await Task.sleep(for: .milliseconds(50))
        }

        if abortRequested {
            throw FlowRunnerError.aborted
        }
    }
}

public final class FlowRunner: Runner {
    private let windowBinder: WindowBinder
    private let frameProvider: FrameProvider
    private let matcher: TemplateMatcher
    private let inputDispatcher: InputDispatcher
    private let diagnostics: DiagnosticsSink
    private let sleeper: Sleeper

    public init(
        windowBinder: WindowBinder,
        frameProvider: FrameProvider,
        matcher: TemplateMatcher,
        inputDispatcher: InputDispatcher,
        diagnostics: DiagnosticsSink = NullDiagnosticsSink(),
        sleeper: Sleeper = SystemSleeper()
    ) {
        self.windowBinder = windowBinder
        self.frameProvider = frameProvider
        self.matcher = matcher
        self.inputDispatcher = inputDispatcher
        self.diagnostics = diagnostics
        self.sleeper = sleeper
    }

    public func run(_ request: FlowRunRequest, control: RunControl) async -> FlowRunReport {
        let startedAt = Date()
        var boundWindow: BoundWindow?
        var results: [RunStepResult] = []
        var finalStatus: RunStatus = .succeeded
        var stopReason: String?

        await diagnostics.append(
            StructuredLogEntry(
                level: .info,
                module: "FlowRunner",
                flowID: request.flow.id,
                message: "Starting flow '\(request.flow.name)' with \(request.flow.steps.count) steps."
            )
        )

        do {
            for step in request.flow.steps where step.enabled {
                try await control.checkpoint()
                let result = try await execute(
                    step,
                    in: request,
                    boundWindow: &boundWindow,
                    control: control
                )
                results.append(result)
                await diagnostics.recordStepResult(result)
            }
        } catch {
            finalStatus = error.asRunStatus
            stopReason = error.localizedDescription
        }

        let finishedAt = Date()
        await diagnostics.append(
            StructuredLogEntry(
                timestamp: finishedAt,
                level: finalStatus == .succeeded ? .info : .error,
                module: "FlowRunner",
                flowID: request.flow.id,
                message: stopReason ?? "Flow completed successfully."
            )
        )

        return FlowRunReport(
            flowID: request.flow.id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: finalStatus,
            stopReason: stopReason,
            stepResults: results
        )
    }

    private func execute(
        _ step: FlowStep,
        in request: FlowRunRequest,
        boundWindow: inout BoundWindow?,
        control: RunControl
    ) async throws -> RunStepResult {
        let startedAt = Date()
        let attempts = step.retryPolicy?.maxAttempts ?? 1
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                try await control.checkpoint()
                try await log(.debug, flowID: request.flow.id, stepID: step.id, "Executing \(step.type.rawValue), attempt \(attempt).")
                try await evaluate(
                    step.preconditions,
                    for: request,
                    in: boundWindow,
                    timeoutMs: step.timeoutMs ?? request.flow.defaultTimeoutMs,
                    pollIntervalMs: max(1, step.params.pollIntervalMs ?? 120),
                    control: control
                )
                try await perform(step, in: request, boundWindow: &boundWindow, control: control)
                try await evaluate(
                    step.postconditions,
                    for: request,
                    in: boundWindow,
                    timeoutMs: step.timeoutMs ?? request.flow.defaultTimeoutMs,
                    pollIntervalMs: max(1, step.params.pollIntervalMs ?? 120),
                    control: control
                )

                let result = RunStepResult(
                    stepID: step.id,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    status: .succeeded,
                    attempts: attempt
                )
                return result
            } catch {
                lastError = error
                if attempt < attempts {
                    let backoff = step.retryPolicy?.backoffMs ?? 0
                    try await log(.warning, flowID: request.flow.id, stepID: step.id, "Attempt \(attempt) failed: \(error.localizedDescription)")
                    try await sleeper.sleep(milliseconds: backoff)
                }
            }
        }

        let reason = lastError?.localizedDescription ?? "Unknown error"
        let result = RunStepResult(
            stepID: step.id,
            startedAt: startedAt,
            finishedAt: Date(),
            status: lastError.asRunStatus,
            reason: reason,
            attempts: attempts
        )
        await diagnostics.recordStepResult(result)
        throw lastError ?? FlowRunnerError.invalidStepParameters("Missing failure reason.")
    }

    private func perform(
        _ step: FlowStep,
        in request: FlowRunRequest,
        boundWindow: inout BoundWindow?,
        control: RunControl
    ) async throws {
        switch step.type {
        case .attachWindow:
            boundWindow = try await windowBinder.attach(using: request.flow.targetHint)

        case .focusWindow:
            let window = try requireWindow(boundWindow)
            try await inputDispatcher.focus(window: window)

        case .wait:
            let duration = step.params.durationMs ?? 0
            try await sleeper.sleep(milliseconds: duration)

        case .waitForAnchor:
            let window = try requireWindow(boundWindow)
            let anchorID = try require(step.params.anchorID, message: "waitForAnchor requires anchorID")
            let anchor = try require(request.anchorsByID[anchorID], error: FlowRunnerError.missingAnchor(anchorID))
            let pollIntervalMs = step.params.pollIntervalMs ?? 120
            let timeoutMs = step.timeoutMs ?? request.flow.defaultTimeoutMs
            try await waitForAnchor(anchor, in: window, timeoutMs: timeoutMs, pollIntervalMs: pollIntervalMs, control: control)

        case .clickAt:
            let window = try requireWindow(boundWindow)
            let point = try require(step.params.point, message: "clickAt requires point")
            let button = step.params.button ?? .left
            try await inputDispatcher.click(at: window.geometry.screenPoint(for: point), button: button)

        case .pressKey:
            let keyCode = try require(step.params.keyCode, message: "pressKey requires keyCode")
            try await inputDispatcher.pressKey(keyCode: keyCode, modifiers: step.params.modifiers)

        case .checkpointScreenshot:
            let window = try requireWindow(boundWindow)
            let frame = try await frameProvider.captureFrame(for: window)
            if let imageData = frame.imageData {
                _ = try await diagnostics.saveScreenshot(imageData, label: step.params.label ?? "checkpoint")
            }
        }
    }

    private func evaluate(
        _ conditions: [StepCondition],
        for request: FlowRunRequest,
        in boundWindow: BoundWindow?,
        timeoutMs: Int,
        pollIntervalMs: Int,
        control: RunControl
    ) async throws {
        guard !conditions.isEmpty else { return }
        let window = try requireWindow(boundWindow)
        let start = Date()

        while true {
            try await control.checkpoint()

            let frame = try await frameProvider.captureFrame(for: window)
            var unmetAnchorNames: [String] = []

            for condition in conditions {
                let anchor = try require(request.anchorsByID[condition.anchorID], error: FlowRunnerError.missingAnchor(condition.anchorID))
                let match = try await matcher.match(anchor: anchor, within: frame)
                let visible = match.confidence >= anchor.threshold
                if visible != condition.expectedVisible {
                    unmetAnchorNames.append(anchor.name)
                }
            }

            if unmetAnchorNames.isEmpty {
                return
            }

            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= timeoutMs {
                throw FlowRunnerError.timeout("Condition not met for \(unmetAnchorNames.joined(separator: ", ")).")
            }

            try await sleeper.sleep(milliseconds: pollIntervalMs)
        }
    }

    private func waitForAnchor(
        _ anchor: Anchor,
        in window: BoundWindow,
        timeoutMs: Int,
        pollIntervalMs: Int,
        control: RunControl
    ) async throws {
        let start = Date()
        while true {
            try await control.checkpoint()
            let frame = try await frameProvider.captureFrame(for: window)
            let match = try await matcher.match(anchor: anchor, within: frame)
            if match.confidence >= anchor.threshold {
                return
            }

            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= timeoutMs {
                throw FlowRunnerError.timeout("Anchor '\(anchor.name)' did not reach threshold \(anchor.threshold).")
            }

            try await sleeper.sleep(milliseconds: pollIntervalMs)
        }
    }

    private func requireWindow(_ boundWindow: BoundWindow?) throws -> BoundWindow {
        guard let boundWindow else {
            throw FlowRunnerError.missingWindow
        }
        return boundWindow
    }

    private func require<T>(_ value: T?, message: String) throws -> T {
        guard let value else {
            throw FlowRunnerError.invalidStepParameters(message)
        }
        return value
    }

    private func require<T>(_ value: T?, error: Error) throws -> T {
        guard let value else { throw error }
        return value
    }

    private func log(_ level: StructuredLogEntry.Level, flowID: UUID, stepID: UUID?, _ message: String) async throws {
        await diagnostics.append(
            StructuredLogEntry(
                level: level,
                module: "FlowRunner",
                flowID: flowID,
                stepID: stepID,
                message: message
            )
        )
    }
}

private extension Optional where Wrapped == Error {
    var asRunStatus: RunStatus {
        switch self {
        case .none:
            return .failed
        case .some(let error):
            return error.asRunStatus
        }
    }
}

private extension Error {
    var asRunStatus: RunStatus {
        if let flowError = self as? FlowRunnerError, flowError == .aborted {
            return .aborted
        }
        return .failed
    }
}
