import Foundation

/// Every codebase, not just a chosen one, so the widget's picker works while the app isn't running.
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

    /// Becomes `incoming`, keeping counts and freshness an earlier write recorded for the same analysis only.
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
