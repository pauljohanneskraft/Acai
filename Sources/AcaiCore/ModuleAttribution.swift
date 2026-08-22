/// Resolves which build module each end of a relationship edge belongs to.
///
/// Honours an edge's `origin` provenance: an edge inferred from an extension declared in a
/// different module than the type it extends originates in the extension's file, so its source
/// module is the extension's — not the extended type's home module. Without this, cross-module
/// extensions manufacture phantom upward dependencies and false module cycles. The target module
/// is always the referenced type's home module.
///
/// Shared by the metrics engine and the quality evaluator so both agree on the same module graph.
public struct ModuleAttribution: Sendable {
    private let resolver: ModuleResolver
    private let idToModule: [String: String]

    /// - Parameter resolver: derives a type's declaring module from its file path.
    /// - Parameter idToModule: each in-codebase type id mapped to its declaring module. Edge
    ///   endpoints not in the map are external and resolve to `nil`.
    public init(resolver: ModuleResolver = .standard, idToModule: [String: String]) {
        self.resolver = resolver
        self.idToModule = idToModule
    }

    public func sourceModule(of edge: Relationship) -> String? {
        if let origin = edge.origin { return resolver.productName(forFilePath: origin) }
        return idToModule[edge.source]
    }

    public func targetModule(of edge: Relationship) -> String? {
        idToModule[edge.target]
    }
}
