/// Assigns collision-free Mermaid node ids within a single diagram.
///
/// `mermaidSafeID` maps every non-alphanumeric character to `_`, so distinct sources such as
/// `A.B` and `A-B` can collapse to the same id (`A_B`) and silently merge two nodes. This
/// allocator keeps the readable base id where unique and disambiguates colliding ones by
/// suffixing `_2`, `_3`, … — every id it hands out is recorded, so suffixed ids can't collide
/// with later bases either.
struct MermaidIDAllocator {
    private var used: Set<String> = []

    mutating func id(for source: String) -> String {
        let base = source.mermaidSafeID
        if used.insert(base).inserted { return base }
        var suffix = 2
        while !used.insert("\(base)_\(suffix)").inserted { suffix += 1 }
        return "\(base)_\(suffix)"
    }
}

extension String {
    /// A Mermaid-safe node/class identifier: letters, numbers and underscores only,
    /// never starting with a digit. Used as the stable id; the human-readable text
    /// is carried in a separate quoted label. Not collision-free on its own — use
    /// ``MermaidIDAllocator`` to assign unique ids across a diagram.
    var mermaidSafeID: String {
        let mapped = String(map { ($0.isLetter || $0.isNumber) ? $0 : "_" })
        guard let first = mapped.first else { return "_" }
        return first.isNumber ? "_" + mapped : mapped
    }

    /// Escapes a string for use inside a Mermaid double-quoted label. Quotes become
    /// the `#quot;` entity and newlines become `<br/>` line breaks.
    var mermaidLabelEscaped: String {
        replacingOccurrences(of: "\"", with: "#quot;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }

    /// Escapes a string for an unquoted edge/transition label. Newlines collapse to
    /// spaces and colons are entity-encoded so they don't terminate the label.
    var mermaidTextEscaped: String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ":", with: "#colon;")
    }

    /// Converts a type string's angle-bracket generics to Mermaid's tilde notation
    /// (`List<Item>` → `List~Item~`), which Mermaid renders without breaking parsing.
    var mermaidGenerics: String {
        replacingOccurrences(of: "<", with: "~")
            .replacingOccurrences(of: ">", with: "~")
    }
}
