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

    /// Replaces the list with `incoming` — one entry per codebase the app still has, so a deleted
    /// one stops being offered — while keeping the counts and freshness a previous write recorded
    /// for the *same* analysis. The app learns a codebase's date, its counts and its freshness at
    /// three different moments, and whichever writes second must not erase the others; a count
    /// recorded against an older analysis is dropped rather than carried forward as current.
    public func merging(_ incoming: [CodebaseWidgetSnapshot]) -> CodebaseWidgetSnapshotList {
        CodebaseWidgetSnapshotList(snapshots: incoming.map { incoming in
            guard let existing = snapshot(for: incoming.codebaseID),
                  existing.analysedAt == incoming.analysedAt
            else { return incoming }
            var merged = incoming
            merged.typeCount = incoming.typeCount ?? existing.typeCount
            merged.findingCount = incoming.findingCount ?? existing.findingCount
            merged.criticalFindingCount = incoming.criticalFindingCount ?? existing.criticalFindingCount
            if incoming.freshnessCheckedAt == nil {
                merged.isOutOfDate = existing.isOutOfDate
                merged.freshnessCheckedAt = existing.freshnessCheckedAt
            }
            return merged
        })
    }
}
