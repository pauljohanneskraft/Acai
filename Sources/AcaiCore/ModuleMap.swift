// MARK: - Project Roots

/// The project roots an artifact was discovered at, deepest first so a root nested inside another
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

    /// Each root's project name: the shortest trailing part of its path no other root ends in, so
    /// `apps/api` and `services/api` stay two projects. `"."` is named `analysedFolder`.
    public func projectNames(analysedFolder: String) -> [String: String] {
        let components = Dictionary(uniqueKeysWithValues: paths.map { path in
            let parts = path.pathComponentsIgnoringDots
            return (path, parts.isEmpty ? [analysedFolder] : parts)
        })
        return components.mapValues { parts in
            let length = (1...parts.count).first { length in
                let suffix = parts.suffix(length)
                return components.values.filter { $0.count >= length && $0.suffix(length) == suffix }.count == 1
            }
            return parts.suffix(length ?? parts.count).joined(separator: "/")
        }
    }
}

// MARK: - Module Map

/// Every source file's build module, resolved once per artifact: `<project>/<module>` when
/// `metadata.discoveredRoots` holds more than one root, otherwise exactly what ``ModuleResolver`` derives.
public struct ModuleMap: Sendable {

    public let resolver: ModuleResolver

    /// `true` when the artifact holds more than one project root, so module names carry their project.
    public let isRootQualified: Bool

    private let roots: ProjectRoots
    private let projectsByRoot: [String: String]
    private var modulesByFilePath: [String: String]

    public init(artifact: CodeArtifact, resolver: ModuleResolver = .standard) {
        self.init(
            roots: artifact.metadata.discoveredRoots.map(\.path),
            filePaths: artifact.metadata.filePaths,
            resolver: resolver
        )
    }

    /// - Parameter filePaths: the paths to resolve up front; any other path is resolved on demand.
    public init(roots: [String], filePaths: [String], resolver: ModuleResolver = .standard) {
        self.resolver = resolver
        self.roots = ProjectRoots(roots)
        self.isRootQualified = self.roots.count > 1
        self.projectsByRoot = isRootQualified ? self.roots.projectNames(analysedFolder: resolver.fallbackGroup) : [:]
        self.modulesByFilePath = [:]
        var modules: [String: String] = [:]
        modules.reserveCapacity(filePaths.count)
        for filePath in filePaths where modules[filePath] == nil {
            modules[filePath] = module(forFilePath: filePath)
        }
        self.modulesByFilePath = modules
    }

    public func module(forFilePath filePath: String) -> String {
        if let cached = modulesByFilePath[filePath] { return cached }
        guard isRootQualified, let root = roots.enclosing(filePath) else {
            return resolver.productName(forFilePath: filePath)
        }
        return resolver.productName(forFilePath: filePath, inRoot: root, project: projectsByRoot[root])
    }

    /// The project a qualified module belongs to; `nil` for an unqualified one.
    public func project(ofModule module: String) -> String? {
        projectsByRoot.values
            .filter { module == $0 || module.hasPrefix("\($0)/") }
            .max { $0.count < $1.count }
    }

    /// Each type's module keyed by type id.
    public func modules(ofTypes types: [TypeDeclaration]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(types.count)
        for type in types {
            result[type.id] = module(forFilePath: type.location?.filePath ?? "")
        }
        return result
    }
}
