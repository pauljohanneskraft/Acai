import Foundation
import AcaiCore

/// Detects Node.js projects (`package.json`) and locates TypeScript / JavaScript sources.
///
/// Source directories come from the manifests wherever they say anything: `package.json`'s
/// `workspaces` globs name a monorepo's packages, and each package's `tsconfig.json` — with its
/// `extends` chain merged and its project `references` followed — names that package's directories.
/// Only a package that declares none falls back to probing for a `src/` subdirectory.
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
        let discovered = discoverSourceDirs(at: root)

        let hasTS = SourceFilePresence(extensions: ["ts", "tsx"]).exist(inAnyOf: discovered.dirs)
        let hasJS = SourceFilePresence(extensions: ["js", "jsx", "mjs"]).exist(inAnyOf: discovered.dirs)

        var specs: [SourceSpec] = []

        if hasTS, request.wants(.typeScript) {
            specs.append(SourceSpec(language: .typeScript, sourceDirs: discovered.dirs))
        }
        if hasJS, request.wants(.javaScript), !hasTS || request.explicitlyWants(.javaScript) {
            specs.append(SourceSpec(language: .javaScript, sourceDirs: discovered.dirs))
        }

        // A manifest that could not be followed is one fact about the project, not one per language, so
        // it is recorded once rather than surfacing the same finding under every spec.
        if !specs.isEmpty {
            specs[0].diagnostics = discovered.diagnostics
        }
        return specs
    }

    /// Every directory the project's manifests declare, and whatever could not be read while finding them.
    private func discoverSourceDirs(at root: URL) -> (dirs: [URL], diagnostics: [ParseDiagnostic]) {
        let reader = TypeScriptProjectReader(notAbove: root)
        let probe = SourceDirectoryProbe(preferring: "src")
        let declaration = NodeWorkspaceDeclaration(in: root)
        guard let globs = declaration.globs else {
            return (
                reader.sourceDirs(ofProjectIn: root) ?? probe.directories(in: root),
                reader.diagnostics + declaration.diagnostics
            )
        }

        let packageRoots = NodeWorkspaces(globs: globs, excludingDirectories: excludedDirectories)
            .packageRoots(in: root)
        var dirs = excludingRoot(reader.sourceDirs(ofProjectIn: root) ?? probe.directories(in: root), of: root)
        for packageRoot in packageRoots {
            dirs += reader.sourceDirs(ofProjectIn: packageRoot) ?? probe.directories(in: packageRoot)
        }
        guard !packageRoots.isEmpty else {
            // Probing still beats finding nothing, so the root's own layout stands in for the packages.
            return (
                (dirs + probe.directories(in: root)).removingDuplicates { $0.path },
                reader.diagnostics + declaration.diagnostics + [unresolvedWorkspacesDiagnostic]
            )
        }
        return (dirs.removingDuplicates { $0.path }, reader.diagnostics + declaration.diagnostics)
    }

    /// A workspace root's own sources, minus the root itself. `src/` reached by probing and an
    /// `include` with no literal prefix (`["**/*.ts"]`, which resolves to the config's own folder)
    /// both land on the root, and admitting it would re-import every package through the back door —
    /// the thing reading the globs is there to avoid.
    private func excludingRoot(_ dirs: [URL], of root: URL) -> [URL] {
        dirs.filter { $0.standardizedFileURL.path != root.standardizedFileURL.path }
    }

    /// Workspaces were declared and not one of them named a package, so the layout on disk is not the
    /// layout they describe. Probing is a guess, and says so.
    private var unresolvedWorkspacesDiagnostic: ParseDiagnostic {
        ParseDiagnostic(
            location: SourceLocation(filePath: manifestName, line: 1, column: 1),
            kind: .incompleteDiscovery,
            message: "This project declares workspaces, but none of them names a directory holding a "
                + "\(manifestName) of its own. Source directories were guessed from the folder layout instead."
        )
    }

    /// Never walked while expanding a workspace glob — the same directories the parser itself skips.
    private var excludedDirectories: Set<String> {
        JSCodeParser().configuration.excludedDirectories
            .union(AcaiConstants.standard.defaultExcludedSourceDirectories)
    }
}
