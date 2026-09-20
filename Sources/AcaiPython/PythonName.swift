import AcaiCore

/// A declared name, read under Python's naming conventions.
struct PythonName {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    /// Python has no access keywords: dunders are public, `__x` is name-mangled private, `_x` is
    /// protected.
    var accessLevel: AccessLevel {
        if text.hasPrefix("__") && text.hasSuffix("__") { return .public }
        if text.hasPrefix("__") { return .private }
        if text.hasPrefix("_") { return .protected }
        return .public
    }
}
