import Foundation

public struct FlowRunRequest: Sendable {
    public var flow: Flow
    public var anchorsByID: [UUID: Anchor]

    public init(flow: Flow, anchorsByID: [UUID: Anchor]) {
        self.flow = flow
        self.anchorsByID = anchorsByID
    }
}

public protocol WindowProvider: Sendable {
    func listWindows() async throws -> [WindowDescriptor]
}

public protocol WindowBinder: Sendable {
    func attach(using hint: TargetHint) async throws -> BoundWindow
}

public protocol FrameProvider: Sendable {
    func captureFrame(for window: BoundWindow) async throws -> CapturedFrame
}

public protocol TemplateMatcher: Sendable {
    func match(anchor: Anchor, within frame: CapturedFrame) async throws -> AnchorMatch
}

public protocol InputDispatcher: Sendable {
    func focus(window: BoundWindow) async throws
    func click(at point: ScreenPoint, button: MouseButton) async throws
    func pressKey(keyCode: String, modifiers: [String]) async throws
}

public protocol FlowRepository: Sendable {
    func listFlows() async throws -> [Flow]
    func loadFlow(id: UUID) async throws -> Flow?
    func saveFlow(_ flow: Flow) async throws
}

public protocol AnchorRepository: Sendable {
    func listAnchors() async throws -> [Anchor]
    func saveAnchor(_ anchor: Anchor) async throws
}

public protocol DiagnosticsSink: Sendable {
    func append(_ entry: StructuredLogEntry) async
    func recordStepResult(_ result: RunStepResult) async
    func saveScreenshot(_ data: Data, label: String) async throws -> Asset
}

public protocol Sleeper: Sendable {
    func sleep(milliseconds: Int) async throws
}

public protocol Runner: Sendable {
    func run(_ request: FlowRunRequest, control: RunControl) async -> FlowRunReport
}

public struct SystemSleeper: Sleeper {
    public init() {}

    public func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

public actor NullDiagnosticsSink: DiagnosticsSink {
    public init() {}

    public func append(_ entry: StructuredLogEntry) async {}

    public func recordStepResult(_ result: RunStepResult) async {}

    public func saveScreenshot(_ data: Data, label: String) async throws -> Asset {
        Asset(kind: "screenshot", filePath: "\(label).png", pixelSize: nil)
    }
}
