import AcaiGit
import Foundation

/// Reads a local git working directory's history. Does file I/O — call off the main actor.
protocol LocalCheckoutInspecting: Sendable {
    func refs(in directory: URL) throws -> [GitCheckout.Ref]
    func currentRef(in directory: URL) throws -> String
    func mergeBase(_ first: String, _ second: String, in directory: URL) throws -> String
}

struct GitCheckoutInspector: LocalCheckoutInspecting {
    func refs(in directory: URL) throws -> [GitCheckout.Ref] {
        try GitCheckout(directory: directory).refs()
    }

    func currentRef(in directory: URL) throws -> String {
        try GitCheckout(directory: directory).currentRef
    }

    func mergeBase(_ first: String, _ second: String, in directory: URL) throws -> String {
        try GitCheckout(directory: directory).mergeBase(first, second)
    }
}
