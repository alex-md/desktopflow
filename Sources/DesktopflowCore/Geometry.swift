import Foundation

public struct ScreenPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScreenSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct ScreenRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var midX: Double { x + (width / 2) }
    public var midY: Double { y + (height / 2) }

    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x.clamped(to: 0...1)
        self.y = y.clamped(to: 0...1)
    }

    public func denormalized(in rect: ScreenRect) -> ScreenPoint {
        ScreenPoint(
            x: rect.x + (rect.width * x),
            y: rect.y + (rect.height * y)
        )
    }
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x.clamped(to: 0...1)
        self.y = y.clamped(to: 0...1)
        self.width = width.clamped(to: 0...1)
        self.height = height.clamped(to: 0...1)
    }

    public func denormalized(in rect: ScreenRect) -> ScreenRect {
        ScreenRect(
            x: rect.x + (rect.width * x),
            y: rect.y + (rect.height * y),
            width: rect.width * width,
            height: rect.height * height
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
