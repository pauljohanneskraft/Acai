import Foundation

// MARK: - Analysis Service

/// Language-agnostic by construction: it holds whatever parsers and project-discovery strategy it
/// is given and knows nothing about any specific language. The standard, batteries-included set of
/// languages is assembled in the composition root (`AcaiLibrary`) as `AnalysisService.standard`.
public struct AnalysisService: Sendable {

    // MARK: - Properties

    public let parsers: [any CodeParser]

    public let projectDiscovery: ProjectDiscovery

    /// Caps how many files a spec parses at once. `nil` (the default) derives the cap from
    /// `ProcessInfo.processInfo.activeProcessorCount`; exposed so tests can force strictly serial
    /// parsing (`1`) for deterministic cancellation/ordering assertions.
    public let fileParsingConcurrencyLimit: Int?

    /// Per-file byte ceiling; a larger file is skipped with a `.skipped` diagnostic rather than
    /// read whole. Defaults to ``AcaiConstants/maximumSourceFileBytes``.
    public let maximumSourceFileBytes: Int

    public var registry: LanguageRegistry { LanguageRegistry(parsers: parsers) }

    /// Every registered language's build-output/dependency directories plus the universal VCS one —
    /// the set both source collection and the `.gitignore` walk skip.
    private var excludedDirectories: Set<String> {
        registry.excludedDirectories.union(AcaiConstants.standard.defaultExcludedSourceDirectories)
    }

    // MARK: - Initialisation

    /// Creates a service from an explicit parser set and discovery strategy. When `projectDiscovery`
    /// is omitted, only the parser-driven `FallbackDetector` is used (no build-system detection); the
    /// composition root supplies the concrete detectors.
    public init(
        parsers: [any CodeParser],
        projectDiscovery: ProjectDiscovery? = nil,
        fileParsingConcurrencyLimit: Int? = nil,
        maximumSourceFileBytes: Int = AcaiConstants.standard.maximumSourceFileBytes
    ) {
        self.parsers = parsers
        self.projectDiscovery = projectDiscovery ?? ProjectDiscovery(
            detectors: [],
            fallback: FallbackDetector(parsers: parsers),
            excludedDirectories: LanguageRegistry(parsers: parsers).excludedDirectories
        )
        self.fileParsingConcurrencyLimit = fileParsingConcurrencyLimit
        self.maximumSourceFileBytes = maximumSourceFileBytes
    }

    // MARK: - Parser Registry

    /// Returning `nil` rather than silently substituting a parser surfaces the bug of a language
    /// reaching analysis without being wired into ``parsers`` (a trap when adding a language)
    /// instead of masking it as mis-parsed by the wrong language.
    public func parser(for language: CodeArtifact.SourceLanguage) -> (any CodeParser)? {
        parsers.first { $0.language == language }
    }

    // MARK: - Project Analysis

    /// `includingFile` is an optional caller-supplied predicate over each candidate file's path
    /// (relative to `rootURL`), checked before a file is read/parsed — the hook a caller-owned
    /// allow/blocklist (e.g. `AcaiApp`'s per-codebase file filter) plugs into. Defaults to including
    /// everything. Kept as a plain path-string predicate so this stays language-agnostic.
    ///
    /// `respectingGitignore` composes the project's own `.gitignore` rules into that same predicate,
    /// so a file the repository ignores is not analyzed. Pass `false` to analyze a tree exactly as it
    /// sits on disk.
    ///
    /// `cache` only replaces parsing an unchanged file; enrichment and cross-file resolution still run
    /// over the whole project, so a warm analysis returns exactly what a cold one would.
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        respectingGitignore: Bool = true,
        reusing cache: AnalysisCache = .disabled,
        includingFile: (String) -> Bool = { _ in true }
    ) async throws -> CodeArtifact {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ValidationError("Source directory does not exist: \(rootURL.path)")
        }

        let gitignore = respectingGitignore
            ? GitignoreFilter(root: rootURL, excludingDirectories: excludedDirectories)
            : nil
        let specs = projectDiscovery.discoverSourceSpecs(in: rootURL, requestedLanguages: allowedLanguages)

        guard !specs.isEmpty else {
            let hint = allowedLanguages.isEmpty
                ? "Use --language to specify a language explicitly."
                : "No \(allowedLanguages.map(\.rawValue).joined(separator: "/")) source files found."
            throw ValidationError("Could not discover any source files in \(rootURL.path). \(hint)")
        }

        let reusable = cache.reusableFragments()
        let discoveredRoots = specs.discoveredRoots(relativeTo: rootURL)
        let modules = ModuleMap(roots: discoveredRoots.map(\.path), filePaths: [])
        var parsedSpecs: [ParsedSpec] = []
        var freshEntries: [String: ParsedFileCache.Entry] = [:]
        for spec in specs.mergedByLanguage {
            if let parsed = try await parseSpec(
                spec, rootURL: rootURL, gitignore: gitignore, fileCache: reusable, includingFile: includingFile
            ) {
                freshEntries.merge(parsed.fileCacheEntries) { _, new in new }
                parsedSpecs.append(parsed.scopingTypeIDs(modules: modules))
            }
        }

        // Only a name one module declares non-privately in several files collides; every spec is in.
        let collisions = CollidingTypeIDs(files: parsedSpecs.flatMap(\.files))
        var combinedArtifact: CodeArtifact?
        for parsed in parsedSpecs {
            if let artifact = assemble(parsed.disambiguating(collisions)) {
                combinedArtifact = combinedArtifact.map { $0.merging(with: artifact) } ?? artifact
            }
        }

        guard let combined = combinedArtifact else {
            throw ValidationError("No source files could be parsed in \(rootURL.path).")
        }
        // Runs on the final cross-spec-merged artifact; the rest of `enriched(using:)` runs
        // per-language-group before specs are merged, so it can't see cross-spec call receivers.
        var result = combined.resolvingCallSiteReceivers()
        result.metadata.discoveredRoots = discoveredRoots
        result.metadata.parseDiagnostics.append(contentsOf: gitignore?.diagnostics ?? [])
        cache.save(freshEntries)
        return result
    }

    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL,
        gitignore: GitignoreFilter?,
        fileCache: ParsedFileCache?,
        includingFile: (String) -> Bool
    ) async throws -> ParsedSpec? {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            return nil
        }
        let collected = collectFiles(
            for: codeParser, in: spec, rootURL: rootURL, gitignore: gitignore, includingFile: includingFile
        )
        guard !collected.files.isEmpty else {
            return ParsedSpec(
                spec: spec, fallback: codeParser.configuration, files: [],
                diagnostics: spec.diagnostics + collected.diagnostics, fileCacheEntries: [:])
        }

        let batch = SourceFileBatchParser(
            codeParser: codeParser, rootURL: rootURL,
            concurrencyLimit: fileParsingConcurrencyLimit, maximumFileBytes: maximumSourceFileBytes
        )
        let parsed = try await batch.parse(collected.files, reusing: fileCache)
        return ParsedSpec(
            spec: spec, fallback: codeParser.configuration,
            files: parsed.files,
            diagnostics: spec.diagnostics + collected.diagnostics + parsed.diagnostics,
            fileCacheEntries: parsed.fileCacheEntries)
    }

    /// Enriches by each file's own `metadata.sourceLanguage`, which may differ from the spec's, in first-seen order.
    private func assemble(_ parsed: ParsedSpec) -> CodeArtifact? {
        var byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact] = [:]
        var order: [CodeArtifact.SourceLanguage] = []
        for file in parsed.files {
            let language = file.metadata.sourceLanguage
            if let existing = byLanguage[language] {
                byLanguage[language] = existing.merging(with: file)
            } else {
                byLanguage[language] = file
                order.append(language)
            }
        }
        let enriched = enrichPerLanguage(
            (byLanguage: byLanguage, order: order), spec: parsed.spec, fallback: parsed.fallback
        )
        guard !parsed.diagnostics.isEmpty else { return enriched }
        var result = enriched ?? CodeArtifact(metadata: CodeArtifact.Metadata(sourceLanguage: parsed.spec.language))
        result.metadata.parseDiagnostics.append(contentsOf: parsed.diagnostics)
        return result
    }

    /// Skips every registered language's build-output/dependency directories (plus the universal VCS
    /// dir), not just `codeParser`'s own, then the spec's own excluded paths, before applying
    /// `includingFile`. A symbolic link the walk could not resolve (dangling, or outside the caller's
    /// security scope) becomes a `.skipped` diagnostic rather than vanishing the way it did before
    /// #303 — the same promise the per-file size ceiling makes for a file that exists but is too big.
    private func collectFiles(
        for codeParser: any CodeParser,
        in spec: SourceSpec,
        rootURL: URL,
        gitignore: GitignoreFilter?,
        includingFile: (String) -> Bool
    ) -> (files: [URL], diagnostics: [ParseDiagnostic]) {
        let exts = Set(codeParser.fileExtensions)
        let excluded = excludedDirectories
        var diagnostics: [ParseDiagnostic] = []
        let files = spec.sourceDirs
            .flatMap { sourceDir -> [URL] in
                FileManager.default.fileURLs(
                    in: sourceDir, withExtensions: exts, excludingDirectories: excluded
                ) { unresolved in
                    diagnostics.append(ParseDiagnostic(
                        location: SourceLocation(filePath: unresolved.relativePath(from: rootURL), line: 0, column: 0),
                        kind: .skipped,
                        message: "symbolic link could not be resolved"
                    ))
                }
            }
            .removingDuplicates { $0.standardizedFileURL.path }
            .filter { !spec.excludes($0) }
            .filter { url in
                let path = url.relativePath(from: rootURL)
                return (gitignore?.includes(path) ?? true) && includingFile(path)
            }
        return (files, diagnostics)
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

/// One spec's files, parsed but not yet enriched, held until collisions across every spec are known.
private struct ParsedSpec {
    let spec: SourceSpec
    let fallback: LanguageConfiguration
    var files: [CodeArtifact]
    let diagnostics: [ParseDiagnostic]
    let fileCacheEntries: [String: ParsedFileCache.Entry]

    func scopingTypeIDs(modules: ModuleMap) -> ParsedSpec {
        var copy = self
        copy.files = files.map { $0.scopingTypeIDs(modules: modules) }
        return copy
    }

    func disambiguating(_ collisions: CollidingTypeIDs) -> ParsedSpec {
        var copy = self
        copy.files = files.map(collisions.disambiguating)
        return copy
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
        if let literal = path.relativeToDirectory(base.path) { return literal }
        if let resolved = resolvingSymlinksInPath().path.relativeToDirectory(base.resolvingSymlinksInPath().path) {
            return resolved
        }
        return lastPathComponent
    }
}

extension String {
    /// The receiver expressed relative to `directory`, or `nil` when it does not sit under it.
    ///
    /// The literal path is tried before the symlink-resolved one so a directory symlinked into the
    /// project keeps the path the user pointed at — `Sources/Foo.swift` rather than wherever the
    /// link happens to land — and a codebase therefore reads the same whether a directory is linked
    /// in or copied in place.
    fileprivate func relativeToDirectory(_ directory: String) -> String? {
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        if self == base { return "" }
        guard hasPrefix(base + "/") else { return nil }
        return String(dropFirst(base.count + 1))
    }
}
