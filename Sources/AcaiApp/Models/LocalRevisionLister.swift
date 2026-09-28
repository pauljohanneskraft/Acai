import AcaiGit
import Foundation

/// A local folder's branches and tags, and what is checked out in it right now.
struct LocalRevisions: Equatable {
    var refs: [GitCheckout.Ref]
    var checkedOut: String?
}

/// Reads a folder's revisions for the analysed-revision picker. Does file I/O — call off the main actor.
struct LocalRevisionLister: Sendable {
    let checkouts: LocalCheckoutInspecting

    /// `nil` when the folder is not inside a git repository; a repository whose refs or HEAD can't be
    /// read still yields what could be read.
    func revisions(in directory: URL) -> LocalRevisions? {
        let refs = try? checkouts.refs(in: directory)
        let checkedOut = try? checkouts.currentRef(in: directory)
        guard refs != nil || checkedOut != nil else { return nil }
        return LocalRevisions(refs: refs ?? [], checkedOut: checkedOut)
    }
}
