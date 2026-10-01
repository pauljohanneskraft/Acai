import Foundation

/// Parsing + the per-file cache bookkeeping, split out of `AnalysisService` itself to keep that
/// type's body within the project's length limit.
extension AnalysisService {

    /// Parses every file concurrently (bounded by `fileParsingConcurrencyLimit`, or the processor
    /// count when unset) and groups results by each file's *own* `metadata.sourceLanguage` rather
    /// than the spec's nominal language — a parser may classify a file differently than the extension
    /// that discovered it (e.g. the C parser owns `.h` but reports C++ for a C++ header). Files merge
    /// back in their original order regardless of completion order, so the result — and therefore
    /// `order`, which preserves first-seen order so the merged artifact's top-level language is
    /// stable — is identical to serial parsing.
    func parseFiles(
        _ files: [URL], using codeParser: any CodeParser, rootURL: URL, fileCache: ParsedFileCache?
    ) async throws -> ParsedFilesOutcome {
        guard !files.isEmpty else {
            return ParsedFilesOutcome(byLanguage: [:], order: [], diagnostics: [], fileCacheEntries: [:])
        }

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
        return ParsedFilesOutcome(
            byLanguage: byLanguage, order: order, diagnostics: diagnostics, fileCacheEntries: cacheEntries
        )
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
}

/// `AnalysisService.parseFiles`'s result. A named type rather than a tuple since it carries four
/// values — over SwiftLint's tuple-member limit.
struct ParsedFilesOutcome {
    let byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact]
    let order: [CodeArtifact.SourceLanguage]
    let diagnostics: [ParseDiagnostic]
    let fileCacheEntries: [String: ParsedFileCache.Entry]
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

/// What `cachePlan` found before any file still needing a fresh parse is scheduled: a cache hit's
/// outcome is already in `outcomeByIndex`, by original position.
private struct FileCachePlan {
    var outcomeByIndex: [ParseOutcome?]
    var fingerprints: [Int: FileFingerprint]
    var cacheEntries: [String: ParsedFileCache.Entry]
    var indicesNeedingParse: [Int]
}
