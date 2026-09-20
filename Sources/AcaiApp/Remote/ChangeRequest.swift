import Foundation

/// A proposed change on a hosted remote — GitHub's pull request, GitLab's merge request. A
/// provider lists these; comparing one needs only git.
struct ChangeRequest: Identifiable, Hashable {
    var number: Int
    var title: String
    var authorLogin: String
    /// The branch the change targets (the "old" side of a three-dot comparison, via its merge-base
    /// with `headRef`).
    var baseRef: String
    /// The branch/SHA carrying the change's own commits (the "new" side).
    var headRef: String
    var state: String

    var id: Int { number }
}
