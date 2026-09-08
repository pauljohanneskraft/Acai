extension String {
    /// The last dot-separated component of a qualified name — `"Foo.Bar.Baz"` → `"Baz"`.
    var shortName: String {
        split(separator: ".").last.map(String.init) ?? self
    }
}
