import Foundation

/// Which of the widget's states to show, decided over the shared snapshots.
public struct CodebaseWidgetPresentation: Sendable {
    public enum State: Equatable, Sendable {
        case nothingShared
        case codebaseMissing
        case notAnalysed(CodebaseWidgetSnapshot)
        case analysed(CodebaseWidgetSnapshot)

        public var snapshot: CodebaseWidgetSnapshot? {
            switch self {
            case .nothingShared, .codebaseMissing:
                nil
            case .notAnalysed(let snapshot), .analysed(let snapshot):
                snapshot
            }
        }
    }

    public let list: CodebaseWidgetSnapshotList

    public init(list: CodebaseWidgetSnapshotList) {
        self.list = list
    }

    /// An unconfigured widget (`nil`) shows the codebase analysed most recently.
    public func state(codebaseID: UUID?) -> State {
        guard !list.snapshots.isEmpty else { return .nothingShared }
        guard let snapshot = chosen(codebaseID: codebaseID) else { return .codebaseMissing }
        return snapshot.hasBeenAnalysed ? .analysed(snapshot) : .notAnalysed(snapshot)
    }

    private func chosen(codebaseID: UUID?) -> CodebaseWidgetSnapshot? {
        guard let codebaseID else { return mostRecentlyAnalysed }
        return list.snapshot(for: codebaseID)
    }

    /// Ties break on name, so an unconfigured widget never flips between two codebases.
    private var mostRecentlyAnalysed: CodebaseWidgetSnapshot? {
        list.snapshots.max { left, right in
            if left.analysedAt != right.analysedAt {
                return (left.analysedAt ?? .distantPast) < (right.analysedAt ?? .distantPast)
            }
            return right.codebaseName.localizedStandardCompare(left.codebaseName) == .orderedAscending
        }
    }
}
