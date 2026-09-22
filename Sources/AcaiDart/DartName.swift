import AcaiCore

/// A declared name, read under Dart's naming conventions.
struct DartName {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    /// Dart has no access keywords: an identifier starting with `_` is private to the library.
    var accessLevel: AccessLevel {
        text.hasPrefix("_") ? .private : .public
    }
}
