/// The textual format a diagram is rendered to.
public enum DiagramFormat: String, Sendable, CaseIterable {
    /// Graphviz DOT (the default; rendered to images via Graphviz).
    case dot
    /// Mermaid — embeds directly in Markdown (GitHub, READMEs, docs sites).
    case mermaid
}
