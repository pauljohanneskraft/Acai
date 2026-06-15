/// The textual format a diagram is rendered to.
public enum DiagramFormat: String, Sendable, CaseIterable {
    /// Graphviz DOT (the default; rendered to images via Graphviz).
    case dot
    /// Mermaid — embeds directly in Markdown (GitHub, READMEs, docs sites).
    case mermaid
}

/// A built diagram paired with both of its renderers, so callers dispatch on
/// `DiagramFormat` exactly once instead of repeating `switch format` per diagram type.
///
/// Each diagram type builds its model, then wraps the DOT and Mermaid render calls in the two
/// closures; `render(_:)` is the single place the format is matched.
public struct DiagramExport {
    private let dot: () -> String
    private let mermaid: () -> String

    public init(dot: @escaping () -> String, mermaid: @escaping () -> String) {
        self.dot = dot
        self.mermaid = mermaid
    }

    public func render(_ format: DiagramFormat) -> String {
        switch format {
        case .dot:
            return dot()
        case .mermaid:
            return mermaid()
        }
    }
}
