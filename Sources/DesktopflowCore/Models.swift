import Foundation

public enum MouseButton: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case center
}

public enum MatchMode: String, Codable, CaseIterable, Sendable {
    case pixelTemplate
    case grayscaleTemplate
}

public enum StepType: String, Codable, CaseIterable, Sendable {
    case attachWindow
    case focusWindow
    case wait
    case waitForAnchor
    case clickAt
    case pressKey
    case checkpointScreenshot
}

public enum RunStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
    case aborted
}

public struct RetryPolicy: Codable, Hashable, Sendable {
    public var maxAttempts: Int
    public var backoffMs: Int

    public init(maxAttempts: Int = 1, backoffMs: Int = 0) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoffMs = max(0, backoffMs)
    }
}

public struct TargetHint: Codable, Hashable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitleContains: String?
    public var ownerPID: Int?

    public init(bundleID: String? = nil, appName: String? = nil, windowTitleContains: String? = nil, ownerPID: Int? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitleContains = windowTitleContains
        self.ownerPID = ownerPID
    }
}

public struct StepCondition: Codable, Hashable, Sendable {
    public var anchorID: UUID
    public var expectedVisible: Bool

    public init(anchorID: UUID, expectedVisible: Bool = true) {
        self.anchorID = anchorID
        self.expectedVisible = expectedVisible
    }
}

public struct StepParameters: Codable, Hashable, Sendable {
    public var point: NormalizedPoint?
    public var button: MouseButton?
    public var anchorID: UUID?
    public var pollIntervalMs: Int?
    public var durationMs: Int?
    public var keyCode: String?
    public var modifiers: [String]
    public var label: String?

    public init(
        point: NormalizedPoint? = nil,
        button: MouseButton? = nil,
        anchorID: UUID? = nil,
        pollIntervalMs: Int? = nil,
        durationMs: Int? = nil,
        keyCode: String? = nil,
        modifiers: [String] = [],
        label: String? = nil
    ) {
        self.point = point
        self.button = button
        self.anchorID = anchorID
        self.pollIntervalMs = pollIntervalMs
        self.durationMs = durationMs
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}

public struct FlowStep: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var ordinal: Int
    public var type: StepType
    public var params: StepParameters
    public var enabled: Bool
    public var timeoutMs: Int?
    public var retryPolicy: RetryPolicy?
    public var preconditions: [StepCondition]
    public var postconditions: [StepCondition]
    public var debugNote: String?

    public init(
        id: UUID = UUID(),
        ordinal: Int,
        type: StepType,
        params: StepParameters = StepParameters(),
        enabled: Bool = true,
        timeoutMs: Int? = nil,
        retryPolicy: RetryPolicy? = nil,
        preconditions: [StepCondition] = [],
        postconditions: [StepCondition] = [],
        debugNote: String? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.type = type
        self.params = params
        self.enabled = enabled
        self.timeoutMs = timeoutMs
        self.retryPolicy = retryPolicy
        self.preconditions = preconditions
        self.postconditions = postconditions
        self.debugNote = debugNote
    }
}

public extension FlowStep {
    static func attachWindow(ordinal: Int) -> FlowStep {
        FlowStep(ordinal: ordinal, type: .attachWindow)
    }

    static func focusWindow(ordinal: Int) -> FlowStep {
        FlowStep(ordinal: ordinal, type: .focusWindow)
    }

    static func wait(ordinal: Int, durationMs: Int) -> FlowStep {
        FlowStep(
            ordinal: ordinal,
            type: .wait,
            params: StepParameters(durationMs: durationMs)
        )
    }

    static func waitForAnchor(ordinal: Int, anchorID: UUID, timeoutMs: Int? = nil, pollIntervalMs: Int = 120) -> FlowStep {
        FlowStep(
            ordinal: ordinal,
            type: .waitForAnchor,
            params: StepParameters(anchorID: anchorID, pollIntervalMs: pollIntervalMs),
            timeoutMs: timeoutMs
        )
    }

    static func clickAt(ordinal: Int, point: NormalizedPoint, button: MouseButton = .left) -> FlowStep {
        FlowStep(
            ordinal: ordinal,
            type: .clickAt,
            params: StepParameters(point: point, button: button)
        )
    }

    static func pressKey(ordinal: Int, keyCode: String, modifiers: [String] = []) -> FlowStep {
        FlowStep(
            ordinal: ordinal,
            type: .pressKey,
            params: StepParameters(keyCode: keyCode, modifiers: modifiers)
        )
    }

    static func checkpointScreenshot(ordinal: Int, label: String) -> FlowStep {
        FlowStep(
            ordinal: ordinal,
            type: .checkpointScreenshot,
            params: StepParameters(label: label)
        )
    }
}

public struct Flow: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var targetHint: TargetHint
    public var defaultTimeoutMs: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var steps: [FlowStep]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        targetHint: TargetHint,
        defaultTimeoutMs: Int = 5_000,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        version: Int = 1,
        steps: [FlowStep]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.targetHint = targetHint
        self.defaultTimeoutMs = defaultTimeoutMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.steps = steps.sorted(by: { $0.ordinal < $1.ordinal })
    }
}

public struct Asset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: String
    public var filePath: String
    public var sha256: String?
    public var pixelSize: ScreenSize?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: String,
        filePath: String,
        sha256: String? = nil,
        pixelSize: ScreenSize? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.filePath = filePath
        self.sha256 = sha256
        self.pixelSize = pixelSize
        self.createdAt = createdAt
    }
}

public struct Anchor: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var name: String
    public var region: NormalizedRect
    public var threshold: Double
    public var matchMode: MatchMode
    public var notes: String

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        name: String,
        region: NormalizedRect,
        threshold: Double,
        matchMode: MatchMode,
        notes: String = ""
    ) {
        self.id = id
        self.assetID = assetID
        self.name = name
        self.region = region
        self.threshold = threshold
        self.matchMode = matchMode
        self.notes = notes
    }
}

public struct WindowDescriptor: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var ownerPID: Int?
    public var windowNumber: Int?

    public init(
        id: UUID = UUID(),
        bundleID: String? = nil,
        appName: String,
        title: String,
        ownerPID: Int? = nil,
        windowNumber: Int? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.ownerPID = ownerPID
        self.windowNumber = windowNumber
    }
}

public struct WindowGeometry: Codable, Hashable, Sendable {
    public var frameRect: ScreenRect
    public var contentRect: ScreenRect

    public init(frameRect: ScreenRect, contentRect: ScreenRect) {
        self.frameRect = frameRect
        self.contentRect = contentRect
    }

    /// Canonical automation coordinates are always normalized against the live content rect.
    /// This keeps preview capture, anchor evaluation, and replay clicks aligned to the game surface.
    public func screenPoint(for normalizedPoint: NormalizedPoint) -> ScreenPoint {
        normalizedPoint.denormalized(in: contentRect)
    }
}

public struct BoundWindow: Codable, Hashable, Sendable {
    public var descriptor: WindowDescriptor
    public var geometry: WindowGeometry

    public init(descriptor: WindowDescriptor, geometry: WindowGeometry) {
        self.descriptor = descriptor
        self.geometry = geometry
    }
}

public struct CapturedFrame: Codable, Hashable, Sendable {
    public var windowID: UUID
    public var timestamp: Date
    public var imageData: Data?
    public var pixelSize: ScreenSize

    public init(windowID: UUID, timestamp: Date = .now, imageData: Data? = nil, pixelSize: ScreenSize) {
        self.windowID = windowID
        self.timestamp = timestamp
        self.imageData = imageData
        self.pixelSize = pixelSize
    }
}

public struct AnchorMatch: Codable, Hashable, Sendable {
    public var confidence: Double
    public var matchedRegion: NormalizedRect?

    public init(confidence: Double, matchedRegion: NormalizedRect? = nil) {
        self.confidence = confidence
        self.matchedRegion = matchedRegion
    }
}

public struct RunStepResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var stepID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var status: RunStatus
    public var reason: String?
    public var attempts: Int
    public var diagnostics: [String: String]
    public var screenshotAssetID: UUID?

    public init(
        id: UUID = UUID(),
        stepID: UUID,
        startedAt: Date,
        finishedAt: Date,
        status: RunStatus,
        reason: String? = nil,
        attempts: Int = 1,
        diagnostics: [String: String] = [:],
        screenshotAssetID: UUID? = nil
    ) {
        self.id = id
        self.stepID = stepID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.reason = reason
        self.attempts = attempts
        self.diagnostics = diagnostics
        self.screenshotAssetID = screenshotAssetID
    }
}

public struct FlowRunReport: Codable, Hashable, Sendable {
    public var id: UUID
    public var flowID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var status: RunStatus
    public var stopReason: String?
    public var stepResults: [RunStepResult]

    public init(
        id: UUID = UUID(),
        flowID: UUID,
        startedAt: Date,
        finishedAt: Date,
        status: RunStatus,
        stopReason: String? = nil,
        stepResults: [RunStepResult]
    ) {
        self.id = id
        self.flowID = flowID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.stopReason = stopReason
        self.stepResults = stepResults
    }
}

public struct StructuredLogEntry: Codable, Hashable, Sendable {
    public enum Level: String, Codable, CaseIterable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    public var timestamp: Date
    public var level: Level
    public var module: String
    public var flowID: UUID?
    public var stepID: UUID?
    public var message: String

    public init(
        timestamp: Date = .now,
        level: Level,
        module: String,
        flowID: UUID? = nil,
        stepID: UUID? = nil,
        message: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.module = module
        self.flowID = flowID
        self.stepID = stepID
        self.message = message
    }
}
