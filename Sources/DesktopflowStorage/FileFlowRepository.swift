import DesktopflowCore
import Foundation

public actor FileFlowRepository: FlowRepository {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func listFlows() async throws -> [Flow] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try urls
            .map { try readFlow(at: $0) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    public func loadFlow(id: UUID) async throws -> Flow? {
        try ensureDirectory()
        let url = flowURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return nil
        }
        return try readFlow(at: url)
    }

    public func saveFlow(_ flow: Flow) async throws {
        try ensureDirectory()
        let data = try encoder.encode(flow)
        try data.write(to: flowURL(for: flow.id), options: [.atomic])
    }

    public func deleteFlow(id: UUID) async throws {
        try ensureDirectory()
        let url = flowURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func flowURL(for id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    private func readFlow(at url: URL) throws -> Flow {
        let data = try Data(contentsOf: url)
        return try decoder.decode(Flow.self, from: data)
    }
}

public actor FileAnchorRepository: AnchorRepository {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func listAnchors() async throws -> [Anchor] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try urls.map { try readAnchor(at: $0) }
    }

    public func saveAnchor(_ anchor: Anchor) async throws {
        try ensureDirectory()
        let data = try encoder.encode(anchor)
        try data.write(to: anchorURL(for: anchor.id), options: [.atomic])
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func anchorURL(for id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    private func readAnchor(at url: URL) throws -> Anchor {
        let data = try Data(contentsOf: url)
        return try decoder.decode(Anchor.self, from: data)
    }
}

public enum WorkspacePaths {
    public static func root() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appending(path: "WorkspaceData")
    }

    public static func flowsDirectory() -> URL {
        root().appending(path: "flows")
    }

    public static func anchorsDirectory() -> URL {
        root().appending(path: "anchors")
    }
}
