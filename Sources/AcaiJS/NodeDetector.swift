import Foundation
import AcaiCore

/// Detects Node.js projects (`package.json`) and locates TypeScript / JavaScript sources.
///
/// Source directories come from the manifests where they say anything: `package.json`'s `workspaces`
/// globs name a monorepo's packages, and each package's `tsconfig.json` — with its `extends` chain
/// merged and its project `references` followed — names that package's directories. Only a package
/// that declares none falls back to probing for a `src/` subdirectory.
public struct NodeDetector: BuildSystemDetector {
    private let manifestName = "package.json"

    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles([manifestName]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let request = LanguageRequest(requestedLanguages)
        var reader = TypeScriptProjectReader(notAbove: root)
        let workspaces = NodeWorkspaces(
            manifestAt: root.appendingPathComponent(manifestName), excludingDirectories: excludedDirectories)
        let packageRoots = workspaces?.packageRoots(in: root) ?? []

        // A workspace root's own sources are whatever it declares — falling back to the root itself
        // would swallow every package and make reading the globs pointless.
        var searchDirs = reader.sourceDirs(ofProjectIn: root)
            ?? (workspaces == nil ? SourceDirectoryProbe(preferring: "src").directories(in: root) : [])
        for packageRoot in packageRoots {
            searchDirs += reader.sourceDirs(ofProjectIn: packageRoot)
                ?? SourceDirectoryProbe(preferring: "src").directories(in: packageRoot)
        }
        searchDirs = searchDirs.removingDuplicates { $0.path }

        let hasTS = SourceFilePresence(extensions: ["ts", "tsx"]).exist(inAnyOf: searchDirs)
        let hasJS = SourceFilePresence(extensions: ["js", "jsx", "mjs"]).exist(inAnyOf: searchDirs)

        var specs: [SourceSpec] = []

        if hasTS, request.wants(.typeScript) {
            specs.append(SourceSpec(language: .typeScript, sourceDirs: searchDirs))
        }
        if hasJS, request.wants(.javaScript), !hasTS || request.explicitlyWants(.javaScript) {
            specs.append(SourceSpec(language: .javaScript, sourceDirs: searchDirs))
        }

        // A broken `tsconfig` graph is one fact about the project, not one per language, so it is
        // recorded once rather than surfacing the same finding under every spec.
        if !specs.isEmpty {
            specs[0].diagnostics = reader.diagnostics
        }
        return specs
    }

    /// Never walked while expanding a workspace glob — the same directories the parser itself skips.
    private var excludedDirectories: Set<String> {
        JSCodeParser().configuration.excludedDirectories
            .union(AcaiConstants.standard.defaultExcludedSourceDirectories)
    }
}
