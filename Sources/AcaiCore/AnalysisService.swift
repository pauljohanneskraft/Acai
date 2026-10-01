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
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        respectingGitignore: Bool = true,
        includingFile: (String) -> Bool = { _ in true }
    ) async throws -> CodeArtifact {
        try await analyzingProject(
            at: rootURL, allowedLanguages: allowedLanguages, respectingGitignore: respectingGitignore,
            fileCache: nil, includingFile: includingFile
        ).artifact
    }

    /// Per-file-cache-aware variant: `fileCache` is consulted before reparsing each file — a hit by
    /// `(relativePath, modified, size)` skips reading and parsing that file entirely — and the
    /// returned cache reflects every file this analysis saw (a changed or new file freshly parsed, an
    /// unchanged one carried forward, a removed one dropped), ready for the caller to persist for the
    /// next analysis of the same tree.
    ///
    /// Enrichment and cross-file resolution (``CodeArtifact/enriched(using:)``,
    /// ``CodeArtifact/resolvingCallSiteReceivers()``) always run over the full merged corpus, exactly
    /// as the cache-free overload does — a cache hit only skips re-parsing a file, never any step that
    /// needs the whole project — so the returned artifact is byte-identical to a cold analysis of the
    /// same tree.
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        respectingGitignore: Bool = true,
        reusing fileCache: ParsedFileCache,
        includingFile: (String) -> Bool = { _ in true }
    ) async throws -> (artifact: CodeArtifact, fileCache: ParsedFileCache) {
        try await analyzingProject(
            at: rootURL, allowedLanguages: allowedLanguages, respectingGitignore: respectingGitignore,
            fileCache: fileCache.validated(forToolVersion: AcaiConstants.standard.toolVersion),
            includingFile: includingFile
        )
    }

    private func analyzingProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage],
        respectingGitignore: Bool,
        fileCache: ParsedFileCache?,
        includingFile: (String) -> Bool
    ) async throws -> (artifact: CodeArtifact, fileCache: ParsedFileCache) {
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

        var combinedArtifact: CodeArtifact?
        var combinedFileCacheEntries: [String: ParsedFileCache.Entry] = [:]

        for spec in specs.mergedByLanguage {
            let parsedSpec = try await parseSpec(
                spec, rootURL: rootURL, gitignore: gitignore, fileCache: fileCache, includingFile: includingFile
            )
            combinedFileCacheEntries.merge(parsedSpec.fileCacheEntries) { _, new in new }
            if let artifact = parsedSpec.artifact {
                combinedArtifact = combinedArtifact.map { $0.merging(with: artifact) } ?? artifact
            }
        }

        guard let combined = combinedArtifact else {
            throw ValidationError("No source files could be parsed in \(rootURL.path).")
        }
        // Runs on the final cross-spec-merged artifact; the rest of `enriched(using:)` runs
        // per-language-group before specs are merged, so it can't see cross-spec call receivers.
        var result = combined.resolvingCallSiteReceivers()
        result.metadata.discoveredRoots = specs.discoveredRoots(relativeTo: rootURL)
        result.metadata.parseDiagnostics.append(contentsOf: gitignore?.diagnostics ?? [])
        let newFileCache = fileCache == nil
            ? ParsedFileCache()
            : ParsedFileCache(
                toolVersion: AcaiConstants.standard.toolVersion, entriesByRelativePath: combinedFileCacheEntries
            )
        return (result, newFileCache)
    }

    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL,
        gitignore: GitignoreFilter?,
        fileCache: ParsedFileCache?,
        includingFile: (String) -> Bool
    ) async throws -> (artifact: CodeArtifact?, fileCacheEntries: [String: ParsedFileCache.Entry]) {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            return (nil, [:])
        }
        let collected = collectFiles(
            for: codeParser, in: spec, rootURL: rootURL, gitignore: gitignore, includingFile: includingFile
        )
        guard !collected.files.isEmpty else {
            let diagnostics = spec.diagnostics + collected.diagnostics
            guard !diagnostics.isEmpty else { return (nil, [:]) }
            var result = CodeArtifact(metadata: CodeArtifact.Metadata(sourceLanguage: spec.language))
            result.metadata.parseDiagnostics.append(contentsOf: diagnostics)
            return (result, [:])
        }

        let parsed = try await parseFiles(collected.files, using: codeParser, rootURL: rootURL, fileCache: fileCache)
        let enriched = enrichPerLanguage(
            (byLanguage: parsed.byLanguage, order: parsed.order), spec: spec, fallback: codeParser.configuration
        )
        let diagnostics = spec.diagnostics + collected.diagnostics + parsed.diagnostics
        guard !diagnostics.isEmpty else { return (enriched, parsed.fileCacheEntries) }
        var result = enriched ?? CodeArtifact(metadata: CodeArtifact.Metadata(sourceLanguage: spec.language))
        result.metadata.parseDiagnostics.append(contentsOf: diagnostics)
        return (result, parsed.fileCacheEntries)
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
            .removingDuplicates { $0 }
            .filter { !spec.excludes($0) }
            .filter { url in
                let path = url.relativePath(from: rootURL)
                return (gitignore?.includes(path) ?? true) && includingFile(path)
            }
        return (files, diagnostics)
    }

    /// Parses every file concurrently (bounded by `fileParsingConcurrencyLimit`, or the processor
    /// count when unset) and groups results by each file's *own* `metadata.sourceLanguage` rather
    /// than the spec's nominal language — a parser may classify a file differently than the extension
    /// that discovered it (e.g. the C parser owns `.h` but reports C++ for a C++ header). Files merge
    /// back in their original order regardless of completion order, so the result — and therefore
    /// `order`, which preserves first-seen order so the merged artifact's top-level language is
    /// stable — is identical to serial parsing.
    private func parseFiles(
        _ files: [URL], using codeParser: any CodeParser, rootURL: URL, fileCache: ParsedFileCache?
    ) async throws -> (
        byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact],
        order: [CodeArtifact.SourceLanguage],
        diagnostics: [ParseDiagnostic],
        fileCacheEntries: [String: ParsedFileCache.Entry]
    ) {
        guard !files.isEmpty else { return ([:], [], [], [:]) }

        let plan = cachePlan(for: files, rootURL: rootURL, fileCache: fileCache)
        var outcomeByIndex = plan.outcomeByIndex
        try await parsingMisses(
            plan.indicesNeedingParse, in: files, using: codeParser, rootURL: rootURL, into: &outcomeByIndex
        )
        let cacheEntries = fileCache == nil ? [:] : freshCacheEntries(
            for: plan.indicesNeedingParse, outcomeByIndex: outcomeByIndex, fingerprints: plan.fingerprints,
            carriedForward: plan.cacheEntries
        )

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
        return (byLanguage, order, diagnostics, cacheEntries)
    }

    /// Resolves every cache hit up front via a file stat (not a read), so only genuine misses need a
    /// parse task of their own. `fingerprints` is kept so a freshly-parsed file's (already-computed)
    /// fingerprint doesn't need a second stat afterward.
    private func cachePlan(for files: [URL], rootURL: URL, fileCache: ParsedFileCache?) -> FileCachePlan {
        let outcomeByIndex = [ParseOutcome?](repeating: nil, count: files.count)
        guard let fileCache else {
            return FileCachePlan(
                outcomeByIndex: outcomeByIndex, fingerprints: [:], cacheEntries: [:],
                indicesNeedingParse: Array(files.indices))
        }

        var mutablePlan = FileCachePlan(
            outcomeByIndex: outcomeByIndex, fingerprints: [:], cacheEntries: [:], indicesNeedingParse: [])
        for (index, file) in files.enumerated() {
            guard let fingerprint = fileFingerprint(for: file, rootURL: rootURL) else {
                mutablePlan.indicesNeedingParse.append(index)
                continue
            }
            mutablePlan.fingerprints[index] = fingerprint
            guard let cached = fileCache.fragment(
                forRelativePath: fingerprint.relativePath, modified: fingerprint.modified, size: fingerprint.size
            ) else {
                mutablePlan.indicesNeedingParse.append(index)
                continue
            }
            mutablePlan.outcomeByIndex[index] = .parsed(cached)
            mutablePlan.cacheEntries[fingerprint.relativePath] = ParsedFileCache.Entry(
                modified: fingerprint.modified, size: fingerprint.size, artifact: cached)
        }
        return mutablePlan
    }

    /// Schedules a parse task per miss, bounded by `fileParsingConcurrencyLimit` (or the processor
    /// count when unset), and writes each result back into `outcomeByIndex` at its original position.
    private func parsingMisses(
        _ indices: [Int], in files: [URL], using codeParser: any CodeParser, rootURL: URL,
        into outcomeByIndex: inout [ParseOutcome?]
    ) async throws {
        guard !indices.isEmpty else { return }
        let concurrency = fileParsingConcurrencyLimit ?? ProcessInfo.processInfo.activeProcessorCount
        let limit = max(1, min(indices.count, concurrency))
        try await withThrowingTaskGroup(of: (index: Int, outcome: ParseOutcome).self) { group in
            var cursor = 0
            func scheduleNext() {
                guard cursor < indices.count else { return }
                let index = indices[cursor]
                cursor += 1
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
    }

    /// `carriedForward` (every cache hit) plus one entry per freshly-parsed miss — together, a
    /// complete cache for exactly the files this analysis saw.
    private func freshCacheEntries(
        for indices: [Int], outcomeByIndex: [ParseOutcome?], fingerprints: [Int: FileFingerprint],
        carriedForward: [String: ParsedFileCache.Entry]
    ) -> [String: ParsedFileCache.Entry] {
        var cacheEntries = carriedForward
        for index in indices {
            guard case .parsed(let artifact) = outcomeByIndex[index], let fingerprint = fingerprints[index] else {
                continue
            }
            cacheEntries[fingerprint.relativePath] = ParsedFileCache.Entry(
                modified: fingerprint.modified, size: fingerprint.size, artifact: artifact)
        }
        return cacheEntries
    }

    /// `(relativePath, modified, size)` for one file — the same fingerprint shape a per-file cache
    /// entry carries — or `nil` when the file's attributes can't be read (it will fail to read for
    /// parsing too, moments later, and surface as the usual `.unreadable` diagnostic there).
    private func fileFingerprint(for file: URL, rootURL: URL) -> FileFingerprint? {
        let resolvedPath = file.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        return FileFingerprint(relativePath: file.relativePath(from: rootURL), modified: modified, size: size)
    }

    /// Reads and parses one file in isolation; a read failure becomes a `.unreadable` diagnostic
    /// rather than failing the whole batch, matching the serial loop's per-file failure isolation.
    ///
    /// The size check resolves the symlink first: `attributesOfItem(atPath:)` does not traverse a
    /// terminal symbolic link, so a link to a huge file reports the length of the *link itself* (a
    /// handful of bytes) and sails under the ceiling. Now that links are followed on purpose, that
    /// would silently reintroduce the unbounded read #303 asks to bound.
    private func parseFile(_ file: URL, using codeParser: any CodeParser, rootURL: URL) -> ParseOutcome {
        let relativePath = file.relativePath(from: rootURL)
        let resolvedPath = file.resolvingSymlinksInPath().path
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
        if let size = (attributes?[.size] as? NSNumber)?.intValue, size > maximumSourceFileBytes {
            return .diagnostic(ParseDiagnostic(
                location: SourceLocation(filePath: relativePath, line: 0, column: 0),
                kind: .skipped,
                message: "\(size) bytes, over the \(maximumSourceFileBytes)-byte per-file ceiling"
            ))
        }
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

/// One file's identity for per-file cache purposes.
private struct FileFingerprint {
    let relativePath: String
    let modified: Date
    let size: Int
}

/// What `AnalysisService.cachePlan` found before any file still needing a fresh parse is scheduled:
/// a cache hit's outcome is already in `outcomeByIndex`, by original position.
private struct FileCachePlan {
    var outcomeByIndex: [ParseOutcome?]
    var fingerprints: [Int: FileFingerprint]
    var cacheEntries: [String: ParsedFileCache.Entry]
    var indicesNeedingParse: [Int]
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
