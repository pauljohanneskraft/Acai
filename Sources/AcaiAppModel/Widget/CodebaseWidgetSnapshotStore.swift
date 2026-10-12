import Foundation

/// One atomically written JSON file; an unreadable or newer file is dropped, not migrated.
public struct CodebaseWidgetSnapshotStore: Sendable {
    public let containerURL: URL

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public init?(container: AppGroupContainer) {
        guard let url = container.url else { return nil }
        self.init(containerURL: url)
    }

    public var fileURL: URL {
        containerURL.appendingPathComponent("CodebaseWidgetSnapshots.json")
    }

    public func load() -> CodebaseWidgetSnapshotList {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(CodebaseWidgetSnapshotList.self, from: data),
              decoded.formatVersion <= CodebaseWidgetSnapshotList.currentFormatVersion
        else { return CodebaseWidgetSnapshotList() }
        return decoded
    }

    public func save(_ list: CodebaseWidgetSnapshotList) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: fileURL, options: .atomic)
    }
}
