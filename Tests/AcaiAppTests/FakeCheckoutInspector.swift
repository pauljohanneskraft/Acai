import Foundation
import AcaiGit
@testable import AcaiApp

/// Answers every directory with the same canned history; a `nil` answer throws, standing in for a
/// folder outside any repository.
struct FakeCheckoutInspector: LocalCheckoutInspecting {
    struct Unreadable: Error {}

    var refs: [GitCheckout.Ref]?
    var currentRef: String?
    var mergeBase: String?
    /// A repository whose refs cannot be read, as opposed to `nil` `refs` (no repository at all).
    var refsAreUnreadable = false

    func refs(in directory: URL) throws -> [GitCheckout.Ref] {
        if refsAreUnreadable { throw Unreadable() }
        guard let refs else { throw GitCheckout.Failure.notAGitRepository(directory.path) }
        return refs
    }

    func currentRef(in directory: URL) throws -> String {
        guard let currentRef else { throw Unreadable() }
        return currentRef
    }

    func mergeBase(_ first: String, _ second: String, in directory: URL) throws -> String {
        guard let mergeBase else { throw Unreadable() }
        return mergeBase
    }
}
