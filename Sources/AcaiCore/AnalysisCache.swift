import Foundation

/// One source tree's per-file parse cache, as a collaborator rather than a value threaded through
/// the analysis: ``AnalysisService`` asks it for the fragments an earlier analysis of the same tree
/// left behind, and hands back what the analysis it has just run saw. Which tree, and where its
/// fragments live, are this type's business and no one else's.
///
/// ``disabled`` is the opt-out for a tree nothing will revisit — a git revision extracted to a
/// temporary directory, or a caller that asked outright for a cold reparse. It reads as empty,
/// discards every write, and costs an analysis nothing: no file is fingerprinted and no cache file
/// is left behind for a path no later analysis would look up.
public struct AnalysisCache: Sendable {

    /// Reuses nothing and persists nothing.
    public static let disabled = AnalysisCache(store: nil, resolvedPath: "")

    private let store: AnalysisStore?
    private let resolvedPath: String

    /// Reads and writes `path`'s fragments in `store`, `path` being the standardized,
    /// symlink-resolved absolute path ``AnalysisStore`` keys every entry on.
    public init(store: AnalysisStore = .standard, forResolvedPath path: String) {
        self.store = store
        self.resolvedPath = path
    }

    /// Reads and writes the cache for the tree at `directory`, standardizing and symlink-resolving
    /// it to the path ``AnalysisStore`` keys on — so a caller holding a `URL` need not normalize it
    /// by hand to converge on the same cache as every other interface.
    public init(store: AnalysisStore = .standard, for directory: URL) {
        self.init(store: store, resolvedPath: directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private init(store: AnalysisStore?, resolvedPath: String) {
        self.store = store
        self.resolvedPath = resolvedPath
    }

    /// Whether anything is cached at all. An analysis skips per-file fingerprinting entirely when
    /// this is `false`, so an uncached analysis costs exactly what it did before caching existed.
    var isEnabled: Bool { store != nil }

    /// The fragments stored for this tree: empty when there are none, when the stored file cannot be
    /// decoded, or when it was written by a tool version whose parse output this build no longer
    /// trusts.
    func reusableFragments() -> ParsedFileCache {
        store?.lookupFileCache(forResolvedPath: resolvedPath) ?? ParsedFileCache()
    }

    /// Replaces this tree's stored fragments with what an analysis just saw. A write failure is
    /// swallowed on purpose: the analysis itself succeeded, and fragments that failed to persist
    /// cost the next analysis a cold parse and nothing else.
    func save(_ fragments: ParsedFileCache) {
        try? store?.writeFileCache(fragments, forResolvedPath: resolvedPath)
    }
}
