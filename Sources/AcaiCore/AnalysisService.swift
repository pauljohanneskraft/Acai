import Foundation

// MARK: - Analysis Service

/// Orchestrates parsing: maps languages to their `CodeParser`, runs files through them,
/// and merges results into a single `CodeArtifact`.
///
/// Language-agnostic by construction: it holds whatever parsers and project-discovery strategy it
/// is given and knows nothing about any specific language. The standard, batteries-included set of
/// languages is assembled in the composition root (`AcaiLibrary`) as `AnalysisService.standard`.
public struct AnalysisService: Sendable {

    // MARK: - Properties

    /// The parsers this service uses, one per supported language.
    public let parsers: [any CodeParser]

    /// The project-discovery coordinator used by `analyzeProject`.
    public let projectDiscovery: ProjectDiscovery

    /// Per-language quirks for the parsers in this service, for downstream stages to look up by
    /// `CodeArtifact.metadata.sourceLanguage`.
    public var registry: LanguageRegistry { LanguageRegistry(parsers: parsers) }

    // MARK: - Initialisation

    /// Creates a service from an explicit parser set and discovery strategy. When `projectDiscovery`
    /// is omitted, only the parser-driven `FallbackDetector` is used (no build-system detection); the
    /// composition root supplies the concrete detectors.
    public init(
        parsers: [any CodeParser],
        projectDiscovery: ProjectDiscovery? = nil
    ) {
        self.parsers = parsers
        self.projectDiscovery = projectDiscovery ?? ProjectDiscovery(
            detectors: [],
            fallback: FallbackDetector(parsers: parsers)
        )
    }

    // MARK: - Parser Registry

    /// Returns the parser registered for `language`, or `nil` when none is registered.
    ///
    /// Returning `nil` rather than silently substituting a parser surfaces the bug of a language
    /// reaching analysis without being wired into ``parsers`` (a trap when adding a language)
    /// instead of masking it as mis-parsed by the wrong language.
    public func parser(for language: CodeArtifact.SourceLanguage) -> (any CodeParser)? {
        parsers.first { $0.language == language }
    }

    // MARK: - Project Analysis

    /// Auto-discovers source directories via `projectDiscovery`, then parses and merges all files.
    ///
    /// `includingFile` is an optional caller-supplied predicate over each candidate file's path
    /// (relative to `rootURL`), checked before a file is read/parsed — the hook a caller-owned
    /// allow/blocklist (e.g. `AcaiApp`'s per-codebase file filter) plugs into. Defaults to including
    /// everything. Kept as a plain path-string predicate so this stays language-agnostic.
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        includingFile: (String) -> Bool = { _ in true }
    ) throws -> CodeArtifact {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ValidationError("Source directory does not exist: \(rootURL.path)")
        }

        let specs = projectDiscovery.discoverSourceSpecs(in: rootURL, requestedLanguages: allowedLanguages)

        guard !specs.isEmpty else {
            let hint = allowedLanguages.isEmpty
                ? "Use --language to specify a language explicitly."
                : "No \(allowedLanguages.map(\.rawValue).joined(separator: "/")) source files found."
            throw ValidationError("Could not discover any source files in \(rootURL.path). \(hint)")
        }

        var combinedArtifact: CodeArtifact?

        for spec in specs {
            if let artifact = try parseSpec(spec, rootURL: rootURL, includingFile: includingFile) {
                combinedArtifact = combinedArtifact.map { $0.merging(with: artifact) } ?? artifact
            }
        }

        guard let result = combinedArtifact else {
            throw ValidationError("No source files could be parsed in \(rootURL.path).")
        }
        // Runs on the final cross-spec-merged artifact; the rest of `enriched(using:)` runs
        // per-language-group before specs are merged, so it can't see cross-spec call receivers.
        return result.resolvingCallSiteReceivers()
    }

    /// Parses all files for a single language spec and returns the combined artifact.
    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL,
        includingFile: (String) -> Bool
    ) throws -> CodeArtifact? {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            print("Warning: No parser registered for language \(spec.language.rawValue); skipping it.")
            return nil
        }
        let files = collectFiles(for: codeParser, in: spec, rootURL: rootURL, includingFile: includingFile)
        guard !files.isEmpty else { return nil }

        let parsed = try parseFiles(files, using: codeParser, rootURL: rootURL)
        return enrichPerLanguage(parsed, spec: spec, fallback: codeParser.configuration)
    }

    /// Collects the spec's source files for `codeParser`, skipping every registered language's
    /// build-output/dependency directories (plus the universal VCS dir), then `includingFile`.
    private func collectFiles(
        for codeParser: any CodeParser, in spec: SourceSpec, rootURL: URL, includingFile: (String) -> Bool
    ) -> [URL] {
        let exts = Set(codeParser.fileExtensions)
        let excludedDirectories = registry.excludedDirectories
            .union(AcaiConstants.standard.defaultExcludedSourceDirectories)
        return spec.sourceDirs
            .flatMap {
                FileManager.default.fileURLs(
                    in: $0, withExtensions: exts, excludingDirectories: excludedDirectories
                )
            }
            .removingDuplicates { $0 }
            .filter { includingFile($0.relativePath(from: rootURL)) }
    }

    /// Parses every file and groups results by each file's *own* `metadata.sourceLanguage` rather than
    /// the spec's nominal language — a parser may classify a file differently than the extension that
    /// discovered it (e.g. the C parser owns `.h` but reports C++ for a C++ header). `order` preserves
    /// first-seen order so the merged artifact's top-level language is stable.
    private func parseFiles(
        _ files: [URL], using codeParser: any CodeParser, rootURL: URL
    ) throws -> (byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact], order: [CodeArtifact.SourceLanguage]) {
        var byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact] = [:]
        var order: [CodeArtifact.SourceLanguage] = []
        for file in files {
            try Task.checkCancellation()
            let relativePath = file.relativePath(from: rootURL)
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                let parsed = codeParser.parse(source: source, fileName: relativePath)
                let language = parsed.metadata.sourceLanguage
                if let existing = byLanguage[language] {
                    byLanguage[language] = existing.merging(with: parsed)
                } else {
                    byLanguage[language] = parsed
                    order.append(language)
                }
            } catch {
                print("Warning: Failed to parse \(relativePath): \(error.localizedDescription)")
            }
        }
        return (byLanguage, order)
    }

    /// Runs the enrichment pipeline once per detected language, each with that language's configuration
    /// (resolved from the registry; `fallback` covers a language the registry doesn't know). The spec's
    /// nominal language is emitted first so the merged artifact's top-level `sourceLanguage` matches it.
    private func enrichPerLanguage(
        _ parsed: (byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact], order: [CodeArtifact.SourceLanguage]),
        spec: SourceSpec,
        fallback: LanguageConfiguration
    ) -> CodeArtifact? {
        var order = parsed.order
        guard !order.isEmpty else { return nil }
        if let index = order.firstIndex(of: spec.language), index != 0 {
            order.remove(at: index)
            order.insert(spec.language, at: 0)
        }

        var result: CodeArtifact?
        for language in order {
            guard let group = parsed.byLanguage[language] else { continue }
            let configuration = registry.configuration(for: language) ?? fallback
            // Stamp each type with its language before enrichment so provenance survives into the
            // merged artifact for later per-type classification.
            let enriched = group.stampingSourceLanguage(language).enriched(configuration: configuration)
            result = result.map { $0.merging(with: enriched) } ?? enriched
        }

        guard var combined = result else { return nil }
        if combined.metadata.toolVersion == nil {
            combined.metadata.toolVersion = AcaiConstants.standard.toolVersion
        }
        return combined
    }
}

extension URL {
    /// Returns a path relative to `base`, or the last path component if unrelated.
    /// Comparison is on a path-component boundary so a sibling directory sharing a name prefix
    /// (e.g. `/a/foobar` vs. base `/a/foo`) is treated as unrelated rather than yielding a corrupted
    /// `bar/...` relative path.
    ///
    /// Both sides are symlink-resolved before comparing: the directory enumerator canonicalizes paths
    /// it walks, while `base` (as passed to `analyzeProject(at:)`) often isn't (e.g. `/var/...` on a
    /// platform where it's a symlink to `/private/var/...`). Comparing raw strings there would fail
    /// the prefix check for every file, collapsing every path to a bare filename.
    func relativePath(from base: URL) -> String {
        let resolvedSelf = resolvingSymlinksInPath().path
        let resolvedBasePath = base.resolvingSymlinksInPath().path
        let basePath = resolvedBasePath.hasSuffix("/") ? String(resolvedBasePath.dropLast()) : resolvedBasePath
        if resolvedSelf == basePath {
            return ""
        }
        if resolvedSelf.hasPrefix(basePath + "/") {
            return String(resolvedSelf.dropFirst(basePath.count + 1))
        }
        return lastPathComponent
    }
}
