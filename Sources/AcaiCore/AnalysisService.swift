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
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage]
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
            if let artifact = parseSpec(spec, rootURL: rootURL) {
                combinedArtifact = combinedArtifact.map { $0.merging(with: artifact) } ?? artifact
            }
        }

        guard let result = combinedArtifact else {
            throw ValidationError("No source files could be parsed in \(rootURL.path).")
        }
        // Runs on the *final* cross-spec-merged artifact — the rest of `enriched(using:)` runs
        // per-language-group inside `parseSpec`/`enrichPerLanguage`, before specs are merged, so it
        // can't see calls whose receiver's declaring type lives in a different spec/source directory.
        return result.resolvingCallSiteReceivers()
    }

    /// Parses all files for a single language spec and returns the combined artifact.
    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL
    ) -> CodeArtifact? {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            print("Warning: No parser registered for language \(spec.language.rawValue); skipping it.")
            return nil
        }
        let files = collectFiles(for: codeParser, in: spec)
        guard !files.isEmpty else { return nil }

        let parsed = parseFiles(files, using: codeParser, rootURL: rootURL)
        return enrichPerLanguage(parsed, spec: spec, fallback: codeParser.configuration)
    }

    /// Collects the spec's source files for `codeParser`, skipping every registered language's
    /// build-output/dependency directories (plus the universal VCS dir).
    private func collectFiles(for codeParser: any CodeParser, in spec: SourceSpec) -> [URL] {
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
    }

    /// Parses every file and groups the results by each file's *own* `metadata.sourceLanguage` rather
    /// than the spec's nominal language. A parser may legitimately classify a file as a different
    /// language than the one whose extensions discovered it — e.g. the C parser owns `.h`, but a
    /// header containing C++ constructs is parsed as, and reports, C++. The returned `order` preserves
    /// first-seen order so the merged artifact's top-level language is stable.
    private func parseFiles(
        _ files: [URL], using codeParser: any CodeParser, rootURL: URL
    ) -> (byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact], order: [CodeArtifact.SourceLanguage]) {
        var byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact] = [:]
        var order: [CodeArtifact.SourceLanguage] = []
        for file in files {
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

    /// Runs the generalizable enrichment pipeline (extension resolution, name→id resolution,
    /// inheritance/conformance reclassification, inferred structural edges, dedup) once per detected
    /// language, each with *that* language's configuration (resolved from the registry, keyed on the
    /// artifact's own `metadata.sourceLanguage` — never hard-coded here; `fallback` covers a language
    /// the registry doesn't know). The spec's nominal language is emitted first so the merged
    /// artifact's top-level `sourceLanguage` matches the spec when that language is present.
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
            // Stamp each type with its own language *before* enrichment so the provenance survives into
            // the merged artifact and a later `LanguageConfigurationResolver` can classify per type. Each
            // group is single-language, so the single-config `enriched` convenience is exact here.
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
    /// Comparison is on a path-component boundary so a sibling directory sharing a name
    /// prefix (e.g. `/a/foobar` against base `/a/foo`) is treated as unrelated rather than
    /// yielding a corrupted `bar/...` relative path.
    func relativePath(from base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path
        if path == basePath {
            return ""
        }
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return lastPathComponent
    }
}
