import Foundation

/// Which of a batch's files a ``ParsedFileCache`` already answers for, worked out up front from a
/// file stat rather than a read — so only a genuine miss costs a parse task.
struct ParsedFileBatchPlan {

    /// A cache hit's outcome, already filled in at the file's original position; a miss stays `nil`
    /// until it has been parsed.
    let outcomeByIndex: [FileOutcome?]

    /// The files still to parse, by their position in the batch.
    let indicesNeedingParse: [Int]

    /// Kept so a freshly parsed file's (already computed) fingerprint needs no second stat.
    private let fingerprints: [Int: SourceFileFingerprint]

    /// Every cache hit, ready to be carried into the next cache unchanged.
    private let carriedForward: [String: ParsedFileCache.Entry]

    /// A `nil` cache plans every file as a miss and fingerprints none of them, so a caller that is
    /// not caching pays nothing for the fact that caching exists.
    init(files: [URL], rootURL: URL, cache: ParsedFileCache?) {
        var outcomeByIndex = [FileOutcome?](repeating: nil, count: files.count)
        guard let cache else {
            self.outcomeByIndex = outcomeByIndex
            self.indicesNeedingParse = Array(files.indices)
            self.fingerprints = [:]
            self.carriedForward = [:]
            return
        }

        var needingParse: [Int] = []
        var fingerprints: [Int: SourceFileFingerprint] = [:]
        var carriedForward: [String: ParsedFileCache.Entry] = [:]
        for (index, file) in files.enumerated() {
            guard let fingerprint = SourceFileFingerprint(file: file, relativeTo: rootURL) else {
                needingParse.append(index)
                continue
            }
            fingerprints[index] = fingerprint
            guard let cached = cache.fragment(for: fingerprint) else {
                needingParse.append(index)
                continue
            }
            outcomeByIndex[index] = .parsed(cached)
            carriedForward[fingerprint.relativePath] = fingerprint.entry(for: cached)
        }
        self.outcomeByIndex = outcomeByIndex
        self.indicesNeedingParse = needingParse
        self.fingerprints = fingerprints
        self.carriedForward = carriedForward
    }

    /// Every cache hit carried forward plus one entry per freshly parsed miss — together, a complete
    /// cache for exactly the files this batch saw, so a file removed since the last analysis is
    /// dropped rather than accumulating forever.
    func cacheEntries(addingFreshlyParsed parsed: [FileOutcome?]) -> [String: ParsedFileCache.Entry] {
        var entries = carriedForward
        for index in indicesNeedingParse {
            guard case .parsed(let artifact) = parsed[index], let fingerprint = fingerprints[index] else { continue }
            entries[fingerprint.relativePath] = fingerprint.entry(for: artifact)
        }
        return entries
    }
}
