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

    public var registry: LanguageRegistry { LanguageRegistry(parsers: parsers) }

    // MARK: - Initialisation

    /// Creates a service from an explicit parser set and discovery strategy. When `projectDiscovery`
    /// is omitted, only the parser-driven `FallbackDetector` is used (no build-system detection); the
    /// composition root supplies the concrete detectors.
    public init(
        parsers: [any CodeParser],
        projectDiscovery: ProjectDiscovery? = nil,
        fileParsingConcurrencyLimit: Int? = nil
    ) {
        self.parsers = parsers
        self.projectDiscovery = projectDiscovery ?? ProjectDiscovery(
            detectors: [],
            fallback: FallbackDetector(parsers: parsers)
        )
        self.fileParsingConcurrencyLimit = fileParsingConcurrencyLimit
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
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        includingFile: (String) -> Bool = { _ in true }
    ) async throws -> CodeArtifact {
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
            if let artifact = try await parseSpec(spec, rootURL: rootURL, includingFile: includingFile) {
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

    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL,
        includingFile: (String) -> Bool
    ) async throws -> CodeArtifact? {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            return nil
        }
        let files = collectFiles(for: codeParser, in: spec, rootURL: rootURL, includingFile: includingFile)
        guard !files.isEmpty else { return nil }

        let parsed = try await parseFiles(files, using: codeParser, rootURL: rootURL)
        let enriched = enrichPerLanguage(
            (byLanguage: parsed.byLanguage, order: parsed.order), spec: spec, fallback: codeParser.configuration
        )
        guard !parsed.diagnostics.isEmpty else { return enriched }
        var result = enriched ?? CodeArtifact(metadata: CodeArtifact.Metadata(sourceLanguage: spec.language))
        result.metadata.parseDiagnostics.append(contentsOf: parsed.diagnostics)
        return result
    }

    /// Skips every registered language's build-output/dependency directories (plus the universal VCS
    /// dir), not just `codeParser`'s own, before applying `includingFile`.
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

    /// Parses every file concurrently (bounded by `fileParsingConcurrencyLimit`, or the processor
    /// count when unset) and groups results by each file's *own* `metadata.sourceLanguage` rather
    /// than the spec's nominal language — a parser may classify a file differently than the extension
    /// that discovered it (e.g. the C parser owns `.h` but reports C++ for a C++ header). Files merge
    /// back in their original order regardless of completion order, so the result — and therefore
    /// `order`, which preserves first-seen order so the merged artifact's top-level language is
    /// stable — is identical to serial parsing.
    private func parseFiles(
        _ files: [URL], using codeParser: any CodeParser, rootURL: URL
    ) async throws -> (
        byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact],
        order: [CodeArtifact.SourceLanguage],
        diagnostics: [ParseDiagnostic]
    ) {
        guard !files.isEmpty else { return ([:], [], []) }
        let concurrency = fileParsingConcurrencyLimit ?? ProcessInfo.processInfo.activeProcessorCount
        let limit = max(1, min(files.count, concurrency))

        var outcomeByIndex = [ParseOutcome?](repeating: nil, count: files.count)
        try await withThrowingTaskGroup(of: (index: Int, outcome: ParseOutcome).self) { group in
            var nextIndex = 0
            func scheduleNext() {
                guard nextIndex < files.count else { return }
                let index = nextIndex
                nextIndex += 1
                let file = files[index]
                group.addTask {
                    try Task.checkCancellation()
                    let outcome = self.parseFile(file, using: codeParser, rootURL: rootURL)
                    try Task.checkCancellation()
                    return (index, outcome)
                }
            }
            for _ in 0..<limit { scheduleNext() }
            while let next = try await group.next() {
                outcomeByIndex[next.index] = next.outcome
                scheduleNext()
            }
        }

        var byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact] = [:]
        var order: [CodeArtifact.SourceLanguage] = []
        var diagnostics: [ParseDiagnostic] = []
        for case let outcome? in outcomeByIndex {
            switch outcome {
            case .parsed(let parsed):
                let language = parsed.metadata.sourceLanguage
                if let existing = byLanguage[language] {
                    byLanguage[language] = existing.merging(with: parsed)
                } else {
                    byLanguage[language] = parsed
                    order.append(language)
                }
            case .diagnostic(let diagnostic):
                diagnostics.append(diagnostic)
            }
        }
        return (byLanguage, order, diagnostics)
    }

    /// Reads and parses one file in isolation; a read failure becomes a `.unreadable` diagnostic
    /// rather than failing the whole batch, matching the serial loop's per-file failure isolation.
    private func parseFile(_ file: URL, using codeParser: any CodeParser, rootURL: URL) -> ParseOutcome {
        let relativePath = file.relativePath(from: rootURL)
        do {
            let source = try String(contentsOf: file, encoding: .utf8)
            return .parsed(codeParser.parse(source: source, fileName: relativePath))
        } catch {
            return .diagnostic(ParseDiagnostic(
                location: SourceLocation(filePath: relativePath, line: 0, column: 0),
                kind: .unreadable,
                message: error.localizedDescription
            ))
        }
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

/// The result of reading and parsing one file: either a parsed artifact, or a diagnostic when the
/// file itself couldn't be read.
private enum ParseOutcome: Sendable {
    case parsed(CodeArtifact)
    case diagnostic(ParseDiagnostic)
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
