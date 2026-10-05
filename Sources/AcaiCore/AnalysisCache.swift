import Foundation

/// One source tree's per-file parse cache in an ``AnalysisStore``.
public struct AnalysisCache: Sendable {

    /// Reuses and persists nothing — for a tree no later analysis revisits.
    public static let disabled = AnalysisCache(store: nil, resolvedPath: "")

    private let store: AnalysisStore?
    private let resolvedPath: String
    private let build = ToolBuild.current

    /// `path` is the standardized, symlink-resolved path ``AnalysisStore`` keys entries on.
    public init(store: AnalysisStore = .standard, forResolvedPath path: String) {
        self.init(store: store, resolvedPath: path)
    }

    public init(store: AnalysisStore = .standard, for directory: URL) {
        self.init(store: store, forResolvedPath: directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private init(store: AnalysisStore?, resolvedPath: String) {
        self.store = store
        self.resolvedPath = resolvedPath
    }

    /// `nil` when disabled, so an uncached analysis fingerprints no files.
    func reusableFragments() -> ParsedFileCache? {
        guard let store else { return nil }
        guard let stored = store.lookupFileCache(forResolvedPath: resolvedPath),
              stored.isWritten(by: build)
        else { return ParsedFileCache(build: build) }
        return stored
    }

    /// Best effort: a failed write only costs the next analysis a cold parse.
    func save(_ entries: [String: ParsedFileCache.Entry]) {
        try? store?.writeFileCache(
            ParsedFileCache(build: build, entriesByRelativePath: entries), forResolvedPath: resolvedPath
        )
    }
}
