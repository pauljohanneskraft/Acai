/// The type names a generated artifact draws from. Deliberately hostile: a diagram's DOT and Mermaid
/// identifiers are derived from a type name, so the names that break identifier generation — ones
/// differing only in punctuation, ones that are pure punctuation, language keywords, names with
/// spaces or newlines, non-ASCII names, and a leading digit — have to be in the corpus rather than
/// only well-behaved `CamelCase`.
public struct TypeNameAlphabet: Sendable {
    public static let standard = TypeNameAlphabet()

    public let names: [String]

    public init() {
        names = Self.plain + Self.collapsing + Self.keywords + Self.awkward
    }

    /// Ordinary names, so a generated artifact still looks mostly like real code.
    private static let plain = [
        "Service", "Repository", "Controller", "ViewModel", "Store", "Client", "Parser",
        "Renderer", "Coordinator", "Builder", "Resolver", "Mapper", "Cache", "Session"
    ]

    /// Distinct names that `mermaidSafeID` maps to the same identifier — every non-alphanumeric
    /// character becomes `_`, so these collide and must be disambiguated rather than merged.
    private static let collapsing = [
        "A.B", "A-B", "A B", "A_B", "A:B", "A/B", "A+B",
        "Outer.Inner", "Outer-Inner", "Outer Inner"
    ]

    /// Reserved words in DOT, Mermaid, or a supported source language.
    private static let keywords = [
        "graph", "digraph", "subgraph", "node", "edge", "strict", "class", "classDiagram",
        "end", "style", "click", "direction", "return", "default", "operator"
    ]

    private static let awkward = [
        "", " ", "  ", ".", "-", "_", "::", "…", "«stereotype»", "0Leading", "9",
        "Tipo\u{301}", "Ünïcødé", "日本語型", "emoji🙂Type", "with\"quote", "with\\backslash",
        "with<angle>", "with{brace}", "with|pipe", "with\nnewline", "with\ttab",
        "Generic<Element>", "Dictionary<String, [Int]>", "very" + String(repeating: "Long", count: 30)
    ]
}
