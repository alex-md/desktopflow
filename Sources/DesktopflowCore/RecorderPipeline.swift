import Foundation

public enum RecordedLowLevelEventKind: Hashable, Sendable {
    case mouseDown(button: MouseButton, location: ScreenPoint)
    case keyDown(keyCode: String, modifiers: [String], bundleID: String?)
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
            let rect = window.geometry.contentRect
            let point = NormalizedPoint(
                x: (location.x - rect.x) / rect.width,
                y: (location.y - rect.y) / rect.height
            )
            return FlowStep.clickAt(ordinal: 0, point: point, button: button)

        case .keyDown(let keyCode, let modifiers, let bundleID):
            guard !Self.isModifierOnlyKey(keyCode) else { return nil }

            if let expectedBundleID = window?.descriptor.bundleID ?? targetHint.bundleID,
               let bundleID,
               expectedBundleID != bundleID {
                return nil
            }

            return FlowStep.pressKey(ordinal: 0, keyCode: keyCode, modifiers: modifiers)
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
}
