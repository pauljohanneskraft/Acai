import AcaiCore

extension String {

    /// This name's visibility under Python's naming convention. Python has no access keywords:
    /// dunders are public, `__x` is name-mangled private, `_x` is protected.
    var pythonAccessLevel: AccessLevel {
        if hasPrefix("__") && hasSuffix("__") { return .public }
        if hasPrefix("__") { return .private }
        if hasPrefix("_") { return .protected }
        return .public
    }
}
