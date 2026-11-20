import Foundation

// MARK: - Project Discovery Coordinator

/// Walks the folder looking for project roots, rather than only asking about the folder itself: a
/// directory carrying a build system's indicator file is a root, wherever it sits. Every detector is
/// tried at every directory, and within one directory the first detector that claims a language wins
/// (e.g. SPM takes priority over Xcode for Swift). Across directories they don't compete — two
/// packages side by side are two Swift roots.
///
/// A detected root doesn't stop the descent, since Gradle and CMake nest, but a root's own source
/// directories are not probed again as if they were new roots, and a source directory an ancestor
/// already claimed for a language is not claimed a second time — unless it is one of that ancestor's
/// ``SourceSpec/nestedRootPaths``, which a root found there claims instead.
///
/// Fixture and vendored-project directories (``nonRootDirectories``) are not walked for roots, so a
/// `Package.swift` sitting in a UI-test fixture is not merged into the codebase's own Swift sources.
///
/// The `fallback` detector runs once, at the top, for the languages no root claimed.
public struct ProjectDiscovery: Sendable {
    public let detectors: [any BuildSystemDetector]
    public let fallback: any BuildSystemDetector
    /// Build-output and dependency directories the walk never descends into. The composition root
    /// supplies each language's own (`node_modules`, `.build`, `target`, …) from the registry;
    /// the universal version-control directory is always included.
    public let excludedDirectories: Set<String>
    /// Directory names that never carry a project root, lowercased. A manifest below one belongs to a
    /// fixture or a vendored copy rather than to the codebase being analysed, so the walk does not
    /// look for roots there — unlike ``excludedDirectories``, this is about discovery alone and does
    /// not stop a root above from collecting those files as its own sources.
    public let nonRootDirectories: Set<String>
    /// Counts each path the walk standardises.
    public let pathStandardizationCounter: OperationCounter?
    /// Counts each claim the walk compares a directory against.
    public let claimComparisonCounter: OperationCounter?

    public init(
        detectors: [any BuildSystemDetector],
        fallback: any BuildSystemDetector,
        excludedDirectories: Set<String> = [],
        nonRootDirectories: Set<String> = AcaiConstants.standard.defaultNonRootDirectories,
        pathStandardizationCounter: OperationCounter? = nil,
        claimComparisonCounter: OperationCounter? = nil
    ) {
        self.detectors = detectors
        self.fallback = fallback
        self.excludedDirectories = excludedDirectories
            .union(AcaiConstants.standard.defaultExcludedSourceDirectories)
        self.nonRootDirectories = Set(nonRootDirectories.map { $0.lowercased() })
        self.pathStandardizationCounter = pathStandardizationCounter
        self.claimComparisonCounter = claimComparisonCounter
    }

    public func discoverSourceSpecs(
        in rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        discoverSourceSpecs(in: rootURL, requestedLanguages: requestedLanguages, reading: DirectoryReadCache())
    }

    public func discoverSourceSpecs(
        in rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        reading reads: DirectoryReadCache
    ) -> [SourceSpec] {
        var walk = DiscoveryWalk(discovery: self, requestedLanguages: requestedLanguages, reads: reads)
        walk.descend(into: rootURL)
        guard !Task.isCancelled else { return [] }
        return walk.specs + fallbackSpecs(
            at: rootURL,
            requestedLanguages: requestedLanguages,
            claimed: Set(walk.specs.map(\.language)).union(walk.withheldLanguages),
            reads: reads
        )
    }

    /// Filters the fallback's own output too, because an empty request means "every language" to a
    /// detector that cannot be told which languages are already claimed.
    private func fallbackSpecs(
        at rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        claimed: Set<CodeArtifact.SourceLanguage>,
        reads: DirectoryReadCache
    ) -> [SourceSpec] {
        let specs = (fallback as? any ClaimAwareFallback)?.discoverSourceSpecs(
            at: rootURL, requestedLanguages: requestedLanguages, excluding: claimed, reading: reads
        ) ?? fallback.discoverSourceSpecs(at: rootURL, requestedLanguages: requestedLanguages, reading: reads)
        return specs
            .filter { !claimed.contains($0.language) }
            .map { $0.detected(by: fallback, asFallback: true) }
    }
}

// MARK: - The Walk

/// One traversal's state: the specs collected so far, which source directories are already claimed
/// per language, and which subtrees belong to a root already and are therefore not probed again.
private struct DiscoveryWalk {
    let discovery: ProjectDiscovery
    let requestedLanguages: [CodeArtifact.SourceLanguage]
    let reads: DirectoryReadCache

    var specs: [SourceSpec] = []
    var withheldLanguages: Set<CodeArtifact.SourceLanguage> = []
    private var claimedDirs: [CodeArtifact.SourceLanguage: ClaimIndex] = [:]
    private var claimedSubtrees: ClaimIndex
    private var standardizer: PathStandardizer

    init(discovery: ProjectDiscovery, requestedLanguages: [CodeArtifact.SourceLanguage], reads: DirectoryReadCache) {
        self.discovery = discovery
        self.requestedLanguages = requestedLanguages
        self.reads = reads
        self.claimedSubtrees = ClaimIndex(comparisonCounter: discovery.claimComparisonCounter)
        self.standardizer = PathStandardizer(counter: discovery.pathStandardizationCounter)
    }

    mutating func descend(into directory: URL) {
        guard !Task.isCancelled else { return }
        claim(at: directory)
        for child in subdirectories(of: directory) {
            guard !isInsideClaimedSubtree(child) else { continue }
            descend(into: child)
        }
    }

    private mutating func claim(at directory: URL) {
        var claimedHere: Set<CodeArtifact.SourceLanguage> = []
        for detector in discovery.detectors where detector.isPresent(at: directory, reading: reads) {
            let claim = detector.claim(at: directory, requestedLanguages: requestedLanguages, reading: reads)
            for spec in claim.specs where claimedHere.insert(spec.language).inserted {
                record(spec.detected(by: detector), at: directory)
            }
            withheldLanguages.formUnion(claim.withheldLanguages)
        }
    }

    /// Drops the source directories an ancestor root already claimed for this language — the same
    /// nested Gradle module reached twice, once through its parent's recursion and once through the
    /// walk — and the spec with them when nothing is left.
    private mutating func record(_ spec: SourceSpec, at directory: URL) {
        var spec = spec
        spec.sourceDirs = spec.sourceDirs.filter { !isClaimed($0, for: spec.language) }
        guard !spec.sourceDirs.isEmpty else { return }
        let nestedRoots = spec.nestedRootPaths.map { standardizer.path(of: $0) }
        let claimed = spec.sourceDirs.map {
            ClaimedDirectory(path: standardizer.path(of: $0), nestedRootPaths: nestedRoots)
        }
        let directoryPath = standardizer.path(of: directory)
        let emptyIndex = ClaimIndex(comparisonCounter: discovery.claimComparisonCounter)
        claimedDirs[spec.language, default: emptyIndex].insert(contentsOf: claimed)
        claimedSubtrees.insert(contentsOf: claimed.filter { $0.path != directoryPath })
        specs.append(spec)
    }

    private mutating func isClaimed(_ directory: URL, for language: CodeArtifact.SourceLanguage) -> Bool {
        let path = standardizer.path(of: directory)
        return claimedDirs[language]?.admits(path) ?? false
    }

    private mutating func isInsideClaimedSubtree(_ directory: URL) -> Bool {
        let path = standardizer.path(ofListed: directory)
        return claimedSubtrees.admits(path)
    }

    /// Visible, non-symlinked subdirectories in a stable order, minus the ones that cannot hold a
    /// project root. Symlinks are skipped so the walk can't loop, and hidden directories because a
    /// build system's indicator file never lives in one.
    ///
    /// Filtering here rather than in ``claim(at:)`` is deliberate: a manifest *below* a fixture
    /// directory is a fixture too, so the subtree is not worth walking. The directory the caller
    /// asked about is never filtered, so analysing a fixture package directly still works.
    private func subdirectories(of directory: URL) -> [URL] {
        reads.visibleEntries(of: directory)
            .filter { !discovery.excludedDirectories.contains($0.lastPathComponent) }
            .filter { !discovery.nonRootDirectories.contains($0.lastPathComponent.lowercased()) }
            .filter { entry in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            }
            .sorted { $0.path < $1.path }
    }
}

private struct ClaimedDirectory {
    let path: String
    let nestedRootPaths: [String]

    /// Only the nested-root escape hatch: ``ClaimIndex`` has already matched `candidate` to ``path``.
    func admits(_ candidate: String) -> Bool {
        !nestedRootPaths.contains { candidate.isInside($0) }
    }
}

/// Claims keyed by path, so an ancestor check walks up the candidate rather than scanning every claim.
private struct ClaimIndex {
    let comparisonCounter: OperationCounter?
    private var claimsByPath: [String: [ClaimedDirectory]] = [:]

    init(comparisonCounter: OperationCounter?) {
        self.comparisonCounter = comparisonCounter
    }

    mutating func insert(contentsOf claims: [ClaimedDirectory]) {
        for claim in claims {
            claimsByPath[claim.path, default: []].append(claim)
        }
    }

    func admits(_ candidate: String) -> Bool {
        guard !claimsByPath.isEmpty else { return false }
        var ancestor = Substring(candidate)
        while !ancestor.isEmpty {
            if admits(candidate, claimedAt: String(ancestor)) { return true }
            guard let separator = ancestor.lastIndex(of: "/") else { return false }
            ancestor = ancestor[..<separator]
        }
        return admits(candidate, claimedAt: "/")
    }

    private func admits(_ candidate: String, claimedAt path: String) -> Bool {
        claimsByPath[path]?.contains { claim in
            comparisonCounter?.record()
            return claim.admits(candidate)
        } ?? false
    }
}

private struct PathStandardizer {
    let counter: OperationCounter?
    private var known: [String: String] = [:]

    init(counter: OperationCounter?) {
        self.counter = counter
    }

    mutating func path(of url: URL) -> String {
        if let standardized = known[url.path] { return standardized }
        counter?.record()
        let path = url.standardizedFileURL.path
        let standardized = path.hasSuffix("/") && path != "/" ? String(path.dropLast()) : path
        known[url.path] = standardized
        return standardized
    }

    /// An entry a directory listing returned exists and has no `.` or `..` components, so it
    /// standardises to its standardised parent plus its name without asking the filesystem again.
    mutating func path(ofListed entry: URL) -> String {
        let path = entry.path
        if let standardized = known[path] { return standardized }
        let parent = entry.deletingLastPathComponent().path
        guard let standardizedParent = known[parent] else { return self.path(of: entry) }
        let standardized = standardizedParent == "/"
            ? "/" + entry.lastPathComponent
            : standardizedParent + "/" + entry.lastPathComponent
        known[path] = standardized
        return standardized
    }
}

extension String {
    /// Whether this path is `other` or sits below it, compared on a path-component boundary so
    /// `/a/foobar` is not treated as being inside `/a/foo`.
    fileprivate func isInside(_ other: String) -> Bool {
        self == other || hasPrefix(other.hasSuffix("/") ? other : other + "/")
    }
}
