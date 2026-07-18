/// Shared surface for the Mermaid renderers, mirroring ``DOTRenderer``.
///
/// Every Mermaid diagram starts with the same optional `%%{init …}%%` theme directive; conformers
/// expose their ``theme`` and get ``themePreamble`` in return, so theming threads uniformly across
/// all diagram types instead of each renderer re-deriving the preamble. Backend-specific body syntax
/// stays in each renderer.
public protocol MermaidRenderer: Sendable {
    /// The colour theme to emit, or `nil` for an unthemed diagram.
    var theme: DiagramTheme? { get }
}

extension MermaidRenderer {
    /// The leading Mermaid init directive line(s) for ``theme`` — empty when unthemed. Prepend to
    /// the renderer's output lines.
    public var themePreamble: [String] {
        theme.map { [$0.mermaidInit()] } ?? []
    }
}
