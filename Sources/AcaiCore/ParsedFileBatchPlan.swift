import Foundation

/// Which of a batch's files a ``ParsedFileCache`` already answers for, decided from a stat alone.
struct ParsedFileBatchPlan {

    /// A hit's outcome at its file's position; `nil` for a miss.
    let outcomeByIndex: [FileOutcome?]

    let indicesNeedingParse: [Int]

    private let fingerprints: [Int: SourceFileFingerprint]

    private let carriedForward: [String: ParsedFileCache.Entry]

    /// A `nil` cache plans every file as a miss without fingerprinting any.
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

    /// The hits plus every freshly parsed miss — exactly the files this batch saw, so a removed file
    /// drops out.
    func cacheEntries(addingFreshlyParsed parsed: [FileOutcome?]) -> [String: ParsedFileCache.Entry] {
        var entries = carriedForward
        for index in indicesNeedingParse {
            guard case .parsed(let artifact) = parsed[index], let fingerprint = fingerprints[index] else { continue }
            entries[fingerprint.relativePath] = fingerprint.entry(for: artifact)
        }
        return entries
    }
}
