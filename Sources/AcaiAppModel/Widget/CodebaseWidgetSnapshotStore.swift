import Foundation

/// Reads/writes the widget's snapshot list as one JSON file in the App Group container, following
/// `FilterPresetStore`: sorted-keys pretty-printed encoding, and an atomic write so the widget
/// process can never read a half-written file.
///
/// A file it cannot read or decode is dropped, not migrated — the widget then shows its
/// "nothing shared yet" state, which the app corrects on the next analysis.
public struct CodebaseWidgetSnapshotStore: Sendable {
    public let containerURL: URL

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    /// `nil` when the process holds no App Group entitlement.
    public init?(container: AppGroupContainer) {
        guard let url = container.url else { return nil }
        self.init(containerURL: url)
    }

    public var fileURL: URL {
        containerURL.appendingPathComponent("CodebaseWidgetSnapshots.json")
    }

    /// Does file I/O — call off the main actor.
    public func load() -> CodebaseWidgetSnapshotList {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(CodebaseWidgetSnapshotList.self, from: data),
              decoded.formatVersion <= CodebaseWidgetSnapshotList.currentFormatVersion
        else { return CodebaseWidgetSnapshotList() }
        return decoded
    }

    /// Does file I/O — call off the main actor.
    public func save(_ list: CodebaseWidgetSnapshotList) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: fileURL, options: .atomic)
    }
}
