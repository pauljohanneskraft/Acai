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
    /// A repository whose refs cannot be read — distinct from a `nil` `refs`, which is a folder
    /// outside any repository. Callers tell those two apart, so the fake has to as well.
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
