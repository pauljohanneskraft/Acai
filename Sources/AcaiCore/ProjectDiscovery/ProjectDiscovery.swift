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
/// already claimed for a language is not claimed a second time — unless that ancestor's own manifest
/// declares the directory out of its build, in which case the nested root claims it instead.
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

    public init(
        detectors: [any BuildSystemDetector],
        fallback: any BuildSystemDetector,
        excludedDirectories: Set<String> = [],
        nonRootDirectories: Set<String> = AcaiConstants.standard.defaultNonRootDirectories
    ) {
        self.detectors = detectors
        self.fallback = fallback
        self.excludedDirectories = excludedDirectories
            .union(AcaiConstants.standard.defaultExcludedSourceDirectories)
        self.nonRootDirectories = Set(nonRootDirectories.map { $0.lowercased() })
    }

    public func discoverSourceSpecs(
        in rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        var walk = DiscoveryWalk(discovery: self, requestedLanguages: requestedLanguages)
        walk.descend(into: rootURL)
        return walk.specs + fallbackSpecs(
            at: rootURL,
            requestedLanguages: requestedLanguages,
            claimed: Set(walk.specs.map(\.language)).union(walk.withheldLanguages)
        )
    }

    /// Filters the fallback's own output rather than narrowing the request, because an empty request
    /// means "every language" to a detector — there is no way to ask for "all but these".
    private func fallbackSpecs(
        at rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        claimed: Set<CodeArtifact.SourceLanguage>
    ) -> [SourceSpec] {
        fallback.discoverSourceSpecs(at: rootURL, requestedLanguages: requestedLanguages)
            .filter { !claimed.contains($0.language) }
            .map { $0.detected(by: fallback) }
    }
}

// MARK: - The Walk

/// One traversal's state: the specs collected so far, which source directories are already claimed
/// per language, and which subtrees belong to a root already and are therefore not probed again.
private struct DiscoveryWalk {
    let discovery: ProjectDiscovery
    let requestedLanguages: [CodeArtifact.SourceLanguage]

    var specs: [SourceSpec] = []
    var withheldLanguages: Set<CodeArtifact.SourceLanguage> = []
    private var claimedDirs: [CodeArtifact.SourceLanguage: [ClaimedDirectory]] = [:]
    private var claimedSubtrees: [ClaimedDirectory] = []

    init(discovery: ProjectDiscovery, requestedLanguages: [CodeArtifact.SourceLanguage]) {
        self.discovery = discovery
        self.requestedLanguages = requestedLanguages
    }

    mutating func descend(into directory: URL) {
        claim(at: directory)
        for child in subdirectories(of: directory) where !isInsideClaimedSubtree(child) {
            descend(into: child)
        }
    }

    private mutating func claim(at directory: URL) {
        var claimedHere: Set<CodeArtifact.SourceLanguage> = []
        for detector in discovery.detectors where detector.isPresent(at: directory) {
            let claim = detector.claim(at: directory, requestedLanguages: requestedLanguages)
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
        let excluded = spec.excludedPaths.map(\.standardizedPath)
        let claimed = spec.sourceDirs.map {
            ClaimedDirectory(path: $0.standardizedPath, excludedPaths: excluded)
        }
        claimedDirs[spec.language, default: []].append(contentsOf: claimed)
        claimedSubtrees.append(contentsOf: claimed.filter { $0.path != directory.standardizedPath })
        specs.append(spec)
    }

    private func isClaimed(_ directory: URL, for language: CodeArtifact.SourceLanguage) -> Bool {
        (claimedDirs[language] ?? []).contains { $0.claims(directory.standardizedPath) }
    }

    private func isInsideClaimedSubtree(_ directory: URL) -> Bool {
        claimedSubtrees.contains { $0.claims(directory.standardizedPath) }
    }

    /// Visible, non-symlinked subdirectories in a stable order, minus the ones that cannot hold a
    /// project root. Symlinks are skipped so the walk can't loop, and hidden directories because a
    /// build system's indicator file never lives in one.
    ///
    /// Filtering here rather than in ``claim(at:)`` is deliberate: a manifest *below* a fixture
    /// directory is a fixture too, so the subtree is not worth walking. The directory the caller
    /// asked about is never filtered, so analysing a fixture package directly still works.
    private func subdirectories(of directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { !discovery.excludedDirectories.contains($0.lastPathComponent) }
            .filter { !discovery.nonRootDirectories.contains($0.lastPathComponent.lowercased()) }
            .filter { entry in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            }
            .sorted { $0.path < $1.path }
    }
}

/// A source directory a root claimed, together with the paths under it that the root's own manifest
/// declares out of its build. An excluded path is not claimed, so a root sitting inside one is free to
/// claim it — which is how a build system that composes a project from parts (CMake's
/// `add_subdirectory()`, a manifest's exclusions) keeps each part's boundary.
private struct ClaimedDirectory {
    let path: String
    let excludedPaths: [String]

    func claims(_ candidate: String) -> Bool {
        candidate.isInside(path) && !excludedPaths.contains { candidate.isInside($0) }
    }
}

extension URL {
    fileprivate var standardizedPath: String {
        let path = standardizedFileURL.path
        return path.hasSuffix("/") && path != "/" ? String(path.dropLast()) : path
    }
}

extension String {
    /// Whether this path is `other` or sits below it, compared on a path-component boundary so
    /// `/a/foobar` is not treated as being inside `/a/foo`.
    fileprivate func isInside(_ other: String) -> Bool {
        self == other || hasPrefix(other.hasSuffix("/") ? other : other + "/")
    }
}
