import Foundation
import AcaiGit
@testable import AcaiApp

/// Answers every directory with the same canned history; a `nil` answer throws, standing in for a
/// folder outside any repository or a read that fails.
struct FakeCheckoutInspector: LocalCheckoutInspecting {
    struct Unreadable: Error {}

    var refs: [GitCheckout.Ref]?
    var currentRef: String?
    var mergeBase: String?

    func refs(in directory: URL) throws -> [GitCheckout.Ref] {
        guard let refs else { throw Unreadable() }
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
