/// Controls how types in a `CodeArtifact` are grouped when deriving
/// component-style diagrams (deployment, package, etc.).
public enum DiagramGranularity: String, Codable, Hashable, Sendable, CaseIterable {

    /// Each **source file** is a component node.
    ///
    /// Types in the same file share a node. Cross-file type references
    /// (present in `CodeArtifact.relationships`) produce communication paths
    /// between the corresponding file nodes.
    case fileLevel

    /// Each **namespace / package / module** is a component node.
    ///
    /// Types that share a `namespace` share a node. Types without a namespace
    /// fall into a root node named after the source language. Cross-namespace
    /// references produce communication paths.
    case packageLevel

    /// The entire `CodeArtifact` is a **single** component node.
    ///
    /// Useful when one `CodeArtifact` represents one deployable unit and you
    /// want to compose multiple artifacts externally to show inter-service
    /// communication.
    case artifactLevel
}
