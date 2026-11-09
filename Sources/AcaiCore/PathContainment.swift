import Foundation

extension String {
    /// Whether this path is `other` or sits below it, compared on a path-component boundary so
    /// `/a/foobar` is not treated as being inside `/a/foo`.
    func isInside(_ other: String) -> Bool {
        self == other || hasPrefix(other.hasSuffix("/") ? other : other + "/")
    }
}
