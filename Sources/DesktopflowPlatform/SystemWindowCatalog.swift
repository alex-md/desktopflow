import AppKit
import CoreGraphics
import DesktopflowCore
import Foundation

public enum SystemWindowError: LocalizedError {
    case noMatchingWindow

    public var errorDescription: String? {
        switch self {
        case .noMatchingWindow:
            return "No matching on-screen window could be found."
        }
    }
}

public final class SystemWindowCatalog: @unchecked Sendable, WindowProvider, WindowBinder {
    public init() {}

    public func listWindows() async throws -> [WindowDescriptor] {
        listWindowsSync()
    }

    public func attach(using hint: TargetHint) async throws -> BoundWindow {
        try resolveWindowSync(using: hint)
    }

    public func listWindowsSync() -> [WindowDescriptor] {
        rawWindowInfos()
            .compactMap(makeWindowRecord)
            .map(\.descriptor)
            .filter { descriptor in
                descriptor.ownerPID != Int(ProcessInfo.processInfo.processIdentifier)
            }
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.title < rhs.title
                }
                return lhs.appName < rhs.appName
            }
    }

    public func resolveWindowSync(using hint: TargetHint) throws -> BoundWindow {
        let candidates = rawWindowInfos().compactMap(makeWindowRecord)
        guard let match = candidates.first(where: { matches($0.descriptor, hint: hint) }) else {
            throw SystemWindowError.noMatchingWindow
        }
        return BoundWindow(descriptor: match.descriptor, geometry: match.geometry)
    }

    private func rawWindowInfos() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos
    }

    private func makeWindowRecord(from info: [String: Any]) -> (descriptor: WindowDescriptor, geometry: WindowGeometry)? {
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        guard layer == 0 else { return nil }

        guard
            let boundsValue = info[kCGWindowBounds as String],
            let boundsDictionary = boundsValue as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return nil
        }

        guard bounds.width >= 120, bounds.height >= 120 else {
            return nil
        }

        let appName = (info[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let appName, !appName.isEmpty else {
            return nil
        }

        let title = ((info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? appName

        let ownerPID = info[kCGWindowOwnerPID as String] as? Int
        let windowNumber = info[kCGWindowNumber as String] as? Int
        let bundleID = ownerPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.bundleIdentifier }
        let rect = ScreenRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
        let descriptor = WindowDescriptor(
            bundleID: bundleID,
            appName: appName,
            title: title,
            ownerPID: ownerPID,
            windowNumber: windowNumber
        )

        return (descriptor, WindowGeometry(frameRect: rect, contentRect: rect))
    }

    private func matches(_ descriptor: WindowDescriptor, hint: TargetHint) -> Bool {
        if let ownerPID = hint.ownerPID, descriptor.ownerPID != ownerPID {
            return false
        }

        if let bundleID = hint.bundleID, descriptor.bundleID != bundleID {
            return false
        }

        if let appName = hint.appName, descriptor.appName != appName {
            return false
        }

        if let windowTitleContains = hint.windowTitleContains,
           !descriptor.title.localizedCaseInsensitiveContains(windowTitleContains) {
            return false
        }

        return true
    }
}
