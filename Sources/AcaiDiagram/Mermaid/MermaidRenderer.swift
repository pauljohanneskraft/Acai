/// Shared surface for the Mermaid renderers, mirroring ``DOTRenderer``: conformers expose
/// ``theme`` and get ``themePreamble`` in return, so every diagram threads the same optional
/// `%%{init …}%%` directive instead of each renderer re-deriving it.
public protocol MermaidRenderer: Sendable {
    var theme: DiagramTheme? { get }
}

extension MermaidRenderer {
    public var themePreamble: [String] {
        theme.map { [$0.mermaidInit()] } ?? []
    }
}
