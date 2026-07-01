/// Resolves which build module each end of a relationship edge belongs to.
///
/// It honours an edge's `origin` provenance: an edge inferred from an extension declared in a
/// *different* module than the type it extends (e.g. `CodeArtifact+ClassDiagram` living in the
/// diagram module while `CodeArtifact` lives in the core module) originates in the extension's file,
/// so its *source* module is the extension's module — not the extended type's home module. Without
/// this, such cross-module extensions manufacture phantom upward dependencies and false module
/// cycles. The *target* module is always the referenced type's home module.
///
/// Shared by the metrics engine and the conformance evaluator so coupling numbers and cycle
/// detection agree on the same module graph.
public struct ModuleAttribution: Sendable {
    private let resolver: ModuleResolver
    private let idToModule: [String: String]

    /// - Parameter idToModule: each in-codebase type id mapped to its declaring module (resolved
    ///   from the type's own file). Edge endpoints not in the map are external and resolve to `nil`.
    public init(resolver: ModuleResolver = .standard, idToModule: [String: String]) {
        self.resolver = resolver
        self.idToModule = idToModule
    }

    /// The module the edge originates from: its `origin` file's module when known (the declaring
    /// extension/member), else the source type's home module.
    public func sourceModule(of edge: Relationship) -> String? {
        if let origin = edge.origin { return resolver.productName(forFilePath: origin) }
        return idToModule[edge.source]
    }

    /// The module the edge points into: the target type's home module.
    public func targetModule(of edge: Relationship) -> String? {
        idToModule[edge.target]
    }
}
