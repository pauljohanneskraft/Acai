// MARK: - Project Roots

/// The project roots an artifact was discovered at, ordered so that a root nested inside another
/// claims its own files rather than being swallowed by its ancestor.
public struct ProjectRoots: Sendable {

    /// Longest path first; `"."` (the analysed folder) has no components and so comes last.
    public let paths: [String]

    public init(_ paths: [String]) {
        self.paths = Array(Set(paths)).sorted {
            let (left, right) = ($0.pathComponentsIgnoringDots.count, $1.pathComponentsIgnoringDots.count)
            return left == right ? $0 < $1 : left > right
        }
    }

    public var count: Int { paths.count }

    /// The deepest root that contains `filePath`, or `nil` when no root does.
    public func enclosing(_ filePath: String) -> String? {
        let components = filePath.pathComponentsIgnoringDots
        return paths.first { components.starts(with: $0.pathComponentsIgnoringDots) }
    }
}

// MARK: - Module Map

/// Every source file's build module, resolved once for a whole artifact.
///
/// Two things it does that ``ModuleResolver`` cannot on its own:
///
/// - **It knows how many projects the folder holds.** A path anchor alone names `Core` for two
///   projects that each declare one, collapsing them into a single box. With more than one root in
///   `metadata.discoveredRoots`, every module is qualified as `<root name>/<module>`; with one root
///   the name is exactly what the anchor derives, so a single-project analysis is unchanged.
/// - **It resolves each path once.** Callers used to ask ``ModuleResolver`` per member inside a
///   double loop, re-splitting the same path for every member of every type. This is built once per
///   artifact and handed to the metrics engine, the quality graph and the diagram builders.
///
/// A path the map was not built with still resolves — it is computed on demand rather than answered
/// wrongly — so a location that never reached `metadata.filePaths` is not a silent miss.
///
/// Enrichment is deliberately not a caller: its module key is an internal disambiguation tier of
/// `TypeIdentityResolver`, which indexes by the *unqualified* name, and the two have to agree.
public struct ModuleMap: Sendable {

    public let resolver: ModuleResolver

    /// `true` when the artifact holds more than one project root, so module names carry their
    /// root's. The grouping surfaces read this to decide whether a project box is meaningful.
    public let isRootQualified: Bool

    private let roots: ProjectRoots
    private let modulesByFilePath: [String: String]
    private let projectsByModule: [String: String]

    public init(artifact: CodeArtifact, resolver: ModuleResolver = .standard) {
        self.init(
            roots: artifact.metadata.discoveredRoots.map(\.path),
            filePaths: artifact.metadata.filePaths,
            resolver: resolver
        )
    }

    /// - Parameter roots: project root paths relative to the analysed folder, as
    ///   `CodeArtifact/DiscoveredRoot` records them.
    /// - Parameter filePaths: the paths to resolve up front. Any other path is resolved on demand.
    public init(roots: [String], filePaths: [String], resolver: ModuleResolver = .standard) {
        let roots = ProjectRoots(roots)
        let qualified = roots.count > 1
        var modules: [String: String] = [:]
        var projects: [String: String] = [:]
        modules.reserveCapacity(filePaths.count)
        for filePath in filePaths where modules[filePath] == nil {
            guard qualified, let root = roots.enclosing(filePath) else {
                modules[filePath] = resolver.productName(forFilePath: filePath)
                continue
            }
            let module = resolver.productName(forFilePath: filePath, inRoot: root)
            modules[filePath] = module
            projects[module] = resolver.projectName(ofRoot: root)
        }

        self.resolver = resolver
        self.isRootQualified = qualified
        self.roots = roots
        self.modulesByFilePath = modules
        self.projectsByModule = projects
    }

    public func module(forFilePath filePath: String) -> String {
        if let cached = modulesByFilePath[filePath] { return cached }
        guard isRootQualified, let root = roots.enclosing(filePath) else {
            return resolver.productName(forFilePath: filePath)
        }
        return resolver.productName(forFilePath: filePath, inRoot: root)
    }

    /// The project a module belongs to, or `nil` when the artifact holds a single root and module
    /// names are therefore unqualified.
    public func project(ofModule module: String) -> String? {
        guard isRootQualified else { return nil }
        if let known = projectsByModule[module] { return known }
        guard let separator = module.firstIndex(of: "/") else { return module }
        return String(module[module.startIndex..<separator])
    }

    /// Each type's module keyed by type id — the form `ModuleAttribution`, the metrics engine and
    /// the diagram builders all need.
    public func modules(ofTypes types: [TypeDeclaration]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(types.count)
        for type in types {
            result[type.id] = module(forFilePath: type.location?.filePath ?? "")
        }
        return result
    }
}
