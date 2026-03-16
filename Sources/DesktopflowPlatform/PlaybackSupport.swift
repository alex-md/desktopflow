import DesktopflowCore
import Foundation

public struct PlaceholderFrameProvider: FrameProvider {
    private let pixelSize: ScreenSize

    public init(pixelSize: ScreenSize = ScreenSize(width: 0, height: 0)) {
        self.pixelSize = pixelSize
    }

    public func captureFrame(for window: BoundWindow) async throws -> CapturedFrame {
        CapturedFrame(windowID: window.descriptor.id, imageData: nil, pixelSize: pixelSize)
    }
}

public struct PlaceholderTemplateMatcher: TemplateMatcher {
    public init() {}

    public func match(anchor: Anchor, within frame: CapturedFrame) async throws -> AnchorMatch {
        AnchorMatch(confidence: 0, matchedRegion: nil)
    }
}
