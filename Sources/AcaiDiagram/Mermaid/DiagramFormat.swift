public enum DiagramFormat: String, Sendable, CaseIterable {
    /// The default.
    case dot
    case mermaid
}

/// A built diagram paired with both of its renderers, so callers dispatch on
/// `DiagramFormat` in one place (`render(_:)`) instead of repeating `switch format`.
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
