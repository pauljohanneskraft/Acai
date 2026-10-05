import Foundation

/// Every codebase the app knows about, as last snapshotted. The whole list is written rather than
/// one chosen codebase's entry, because the widget's configuration has to offer a choice of
/// codebase while the app isn't running.
public struct CodebaseWidgetSnapshotList: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion = Self.currentFormatVersion
    public var snapshots: [CodebaseWidgetSnapshot] = []

    public init(snapshots: [CodebaseWidgetSnapshot] = []) {
        self.snapshots = snapshots
    }

    public func snapshot(for codebaseID: UUID) -> CodebaseWidgetSnapshot? {
        snapshots.first { $0.codebaseID == codebaseID }
    }

    /// Replaces one codebase's entry, appending it when the list has none yet, and leaves the rest
    /// untouched — a reindex of one codebase must not drop the others.
    public mutating func update(_ snapshot: CodebaseWidgetSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.codebaseID == snapshot.codebaseID }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
    }

    /// Drops entries for codebases that no longer exist, so a deleted codebase stops being offered.
    public mutating func removeAll(except codebaseIDs: Set<UUID>) {
        snapshots.removeAll { !codebaseIDs.contains($0.codebaseID) }
    }
}
