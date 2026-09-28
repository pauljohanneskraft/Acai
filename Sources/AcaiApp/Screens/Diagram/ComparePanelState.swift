import AcaiGit
import Foundation

/// What the Compare panel shows for one diagram: its ref list, which row the diagram's comparison
/// refs select, and how far the comparison has loaded.
struct ComparePanelState: Equatable {
    /// One row in the ref list: picking a ref enables the diff directly, no on/off step. There's
    /// no "None" row — the panel's `Clear` button turns comparison back off.
    enum Row: Hashable, Identifiable {
        case head
        case ref(GitCheckout.Ref)
        /// Picking this row compares the request's merge-base against its head, not a single ref
        /// against the live working tree — both sides become explicit historical revisions.
        case changeRequest(ChangeRequest)
        case custom

        var id: String {
            switch self {
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.id
            case .changeRequest(let request):
                "pr-\(request.number)"
            case .custom:
                "custom"
            }
        }

        /// The accessibility-identifier suffix — the plain ref name (not `id`'s kind-prefixed form),
        /// so a UI test can target a known fixture ref name without guessing its kind.
        var testIdentifier: String {
            switch self {
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.name
            case .changeRequest(let request):
                "pr-\(request.number)"
            case .custom:
                "custom"
            }
        }
    }

    enum Status: Equatable {
        case failed(String)
        case loading
        case loaded
    }

    var refs: [GitCheckout.Ref] = []
    var changeRequests: [ChangeRequest] = []
    var comparisonGitRef: String?
    var comparisonBaseRef: String?
    var hasOldArtifact = false
    var hasNewArtifact = false
    var error: String?

    /// A literal branch or tag named "HEAD" is left out — the dedicated `.head` row covers it.
    var rows: [Row] {
        [.head] + changeRequests.map(Row.changeRequest)
            + refs.filter { $0.name != "HEAD" }.map(Row.ref) + [.custom]
    }

    var selectedRow: Row? {
        guard let ref = comparisonGitRef else { return nil }
        if let baseRef = comparisonBaseRef {
            return changeRequests.first { $0.headRef == ref && $0.baseRef == baseRef }.map(Row.changeRequest)
        }
        if ref == "HEAD" { return .head }
        if let match = refs.first(where: { $0.name == ref }) { return .ref(match) }
        return .custom
    }

    /// A pull-request comparison needs both the "old" (merge-base) and "new" (head) snapshots; the
    /// other modes only load the "old" side, the "new" side being the live working tree.
    var isFullyLoaded: Bool {
        hasOldArtifact && (comparisonBaseRef == nil || hasNewArtifact)
    }

    /// `nil` while no comparison is selected.
    var status: Status? {
        guard comparisonGitRef != nil else { return nil }
        if let error { return .failed(error) }
        return isFullyLoaded ? .loaded : .loading
    }
}
