import Foundation

/// What the widget should show for a given configuration, decided over the shared snapshot list.
/// Pure, so the decision is unit-testable without a widget host.
public struct CodebaseWidgetPresentation: Sendable {
    public enum State: Equatable, Sendable {
        /// The app has never shared anything — it has not been opened, or holds no codebase yet.
        case nothingShared
        /// The widget names a codebase the app no longer has.
        case codebaseMissing
        /// The codebase exists but has never been analysed.
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

    /// `codebaseID` is `nil` for a widget the user hasn't configured yet, which shows the codebase
    /// analysed most recently rather than nothing at all.
    public func state(codebaseID: UUID?) -> State {
        guard !list.snapshots.isEmpty else { return .nothingShared }
        guard let snapshot = chosen(codebaseID: codebaseID) else { return .codebaseMissing }
        return snapshot.hasBeenAnalysed ? .analysed(snapshot) : .notAnalysed(snapshot)
    }

    private func chosen(codebaseID: UUID?) -> CodebaseWidgetSnapshot? {
        guard let codebaseID else { return mostRecentlyAnalysed }
        return list.snapshot(for: codebaseID)
    }

    /// Ties break on name so an unconfigured widget doesn't flip between two codebases analysed in
    /// the same instant, and a list of never-analysed codebases still shows one.
    private var mostRecentlyAnalysed: CodebaseWidgetSnapshot? {
        list.snapshots.max { left, right in
            if left.analysedAt != right.analysedAt {
                return (left.analysedAt ?? .distantPast) < (right.analysedAt ?? .distantPast)
            }
            return right.codebaseName.localizedStandardCompare(left.codebaseName) == .orderedAscending
        }
    }
}
