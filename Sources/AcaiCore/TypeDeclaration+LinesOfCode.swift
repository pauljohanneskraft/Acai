extension TypeDeclaration {
    /// Every extent this declaration occupies: its own, each member's, and each nested type's,
    /// recursively. Members are included because extension members are merged into the type they
    /// augment, so a Swift or Kotlin type whose behaviour lives in extensions occupies lines in
    /// files its own declaration never reaches.
    public var lineSpans: LineSpanUnion {
        var union = LineSpanUnion()
        union.add(location)
        for member in members { union.add(member.location) }
        for nested in nestedTypes { union.formUnion(nested.lineSpans) }
        return union
    }

    /// Physical lines of code: the distinct lines ``lineSpans`` covers. `0` when no parser supplied
    /// an extent for this declaration or any of its members.
    public var linesOfCode: Int { lineSpans.lineCount }
}
