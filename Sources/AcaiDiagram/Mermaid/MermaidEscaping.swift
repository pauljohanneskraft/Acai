/// `mermaidSafeID` maps every non-alphanumeric character to `_`, so distinct sources such as
/// `A.B` and `A-B` can collapse to the same id (`A_B`) and silently merge two nodes. This
/// allocator disambiguates collisions with a `_2`, `_3`, … suffix.
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

    var mermaidLabelEscaped: String {
        replacingOccurrences(of: "\"", with: "#quot;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }

    /// Colons terminate an unquoted Mermaid label, so they're entity-encoded rather than kept raw.
    var mermaidTextEscaped: String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ":", with: "#colon;")
    }

    /// Mermaid's class-diagram syntax uses `<`/`>` for its own grammar, so generics switch to
    /// tilde notation (`List<Item>` → `List~Item~`) to avoid breaking parsing.
    var mermaidGenerics: String {
        replacingOccurrences(of: "<", with: "~")
            .replacingOccurrences(of: ">", with: "~")
    }
}
