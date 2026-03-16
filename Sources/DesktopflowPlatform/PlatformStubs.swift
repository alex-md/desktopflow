import DesktopflowCore
import Foundation

public enum PlatformStubError: LocalizedError {
    case noWindowsAvailable

    public var errorDescription: String? {
        switch self {
        case .noWindowsAvailable:
            return "No candidate windows are available in the stub platform."
        }
    }
}

public actor StubWindowProvider: WindowProvider {
    private let windows: [WindowDescriptor]

    public init(windows: [WindowDescriptor]) {
        self.windows = windows
    }

    public func listWindows() async throws -> [WindowDescriptor] {
        windows
    }
}

public actor StubWindowBinder: WindowBinder {
    private var boundWindow: BoundWindow

    public init(boundWindow: BoundWindow) {
        self.boundWindow = boundWindow
    }

    public func attach(using hint: TargetHint) async throws -> BoundWindow {
        boundWindow
    }

    public func updateGeometry(_ geometry: WindowGeometry) async {
        boundWindow.geometry = geometry
    }
}

public actor StubFrameProvider: FrameProvider {
    private let pixelSize: ScreenSize
    private let imageData: Data?

    public init(pixelSize: ScreenSize = ScreenSize(width: 1440, height: 900), imageData: Data? = nil) {
        self.pixelSize = pixelSize
        self.imageData = imageData
    }

    public func captureFrame(for window: BoundWindow) async throws -> CapturedFrame {
        CapturedFrame(windowID: window.descriptor.id, imageData: imageData, pixelSize: pixelSize)
    }
}

public actor StubTemplateMatcher: TemplateMatcher {
    private let confidenceByAnchorID: [UUID: Double]

    public init(confidenceByAnchorID: [UUID: Double]) {
        self.confidenceByAnchorID = confidenceByAnchorID
    }

    public func match(anchor: Anchor, within frame: CapturedFrame) async throws -> AnchorMatch {
        AnchorMatch(
            confidence: confidenceByAnchorID[anchor.id] ?? 0,
            matchedRegion: anchor.region
        )
    }
}

public actor RecordingInputDispatcher: InputDispatcher {
    public struct Event: Hashable, Sendable {
        public var kind: String
        public var point: ScreenPoint?
        public var button: MouseButton?
        public var keyCode: String?
        public var modifiers: [String]

        public init(kind: String, point: ScreenPoint? = nil, button: MouseButton? = nil, keyCode: String? = nil, modifiers: [String] = []) {
            self.kind = kind
            self.point = point
            self.button = button
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private(set) public var events: [Event] = []

    public init() {}

    public func focus(window: BoundWindow) async throws {
        events.append(Event(kind: "focus", point: ScreenPoint(x: window.geometry.contentRect.midX, y: window.geometry.contentRect.midY)))
    }

    public func click(at point: ScreenPoint, button: MouseButton) async throws {
        events.append(Event(kind: "click", point: point, button: button))
    }

    public func pressKey(keyCode: String, modifiers: [String]) async throws {
        events.append(Event(kind: "key", keyCode: keyCode, modifiers: modifiers))
    }
}
