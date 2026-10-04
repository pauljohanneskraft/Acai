import Foundation

/// Reads and parses one spec's source files concurrently, merging them back in their original order so
/// the outcome is identical to serial parsing.
///
/// Results are grouped by each file's *own* `metadata.sourceLanguage`, since a parser may classify a
/// file differently than the extension that discovered it (the C parser reports C++ for a C++ header).
struct SourceFileBatchParser {

    struct Outcome {
        let byLanguage: [CodeArtifact.SourceLanguage: CodeArtifact]
        let order: [CodeArtifact.SourceLanguage]
        let diagnostics: [ParseDiagnostic]
        let fileCacheEntries: [String: ParsedFileCache.Entry]

        static let empty = Outcome(byLanguage: [:], order: [], diagnostics: [], fileCacheEntries: [:])
    }

    let codeParser: any CodeParser

    let rootURL: URL

    /// `nil` derives the cap from the processor count.
    let concurrencyLimit: Int?

    let maximumFileBytes: Int

    /// A `nil` cache skips fingerprinting and yields no cache entries.
    func parse(_ files: [URL], reusing cache: ParsedFileCache?) async throws -> Outcome {
        guard !files.isEmpty else { return .empty }

        let plan = ParsedFileBatchPlan(files: files, rootURL: rootURL, cache: cache)
        var outcomeByIndex = plan.outcomeByIndex
        try await parseMisses(plan.indicesNeedingParse, in: files, into: &outcomeByIndex)
        let entries = cache == nil ? [:] : plan.cacheEntries(addingFreshlyParsed: outcomeByIndex)
        return merge(outcomeByIndex, fileCacheEntries: entries)
    }

    // MARK: - Parsing

    private func parseMisses(
        _ indices: [Int], in files: [URL], into outcomeByIndex: inout [FileOutcome?]
    ) async throws {
        guard !indices.isEmpty else { return }
        let concurrency = concurrencyLimit ?? ProcessInfo.processInfo.activeProcessorCount
        let limit = max(1, min(indices.count, concurrency))
        try await withThrowingTaskGroup(of: (index: Int, outcome: FileOutcome).self) { group in
            var cursor = 0
            func scheduleNext() {
                guard cursor < indices.count else { return }
                let index = indices[cursor]
                cursor += 1
                let file = files[index]
                group.addTask {
                    try Task.checkCancellation()
                    let outcome = self.parseFile(file)
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

    /// A read failure becomes a `.unreadable` diagnostic rather than failing the whole batch. The size
    /// check resolves the symlink first, since `attributesOfItem(atPath:)` reports a link's own size.
    private func parseFile(_ file: URL) -> FileOutcome {
        let relativePath = file.relativePath(from: rootURL)
        let resolvedPath = file.resolvingSymlinksInPath().path
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
        if let size = (attributes?[.size] as? NSNumber)?.intValue, size > maximumFileBytes {
            return .diagnostic(ParseDiagnostic(
                location: SourceLocation(filePath: relativePath, line: 0, column: 0),
                kind: .skipped,
                message: "\(size) bytes, over the \(maximumFileBytes)-byte per-file ceiling"
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

    // MARK: - Merging

    private func merge(
        _ outcomeByIndex: [FileOutcome?], fileCacheEntries: [String: ParsedFileCache.Entry]
    ) -> Outcome {
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
        return Outcome(
            byLanguage: byLanguage, order: order, diagnostics: diagnostics, fileCacheEntries: fileCacheEntries
        )
    }
}

enum FileOutcome: Sendable {
    case parsed(CodeArtifact)
    case diagnostic(ParseDiagnostic)
}
