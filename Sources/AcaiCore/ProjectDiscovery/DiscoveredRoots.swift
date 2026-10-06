import Foundation

extension [SourceSpec] {
    /// The distinct project roots these specs were claimed at, in discovery order. One root that
    /// accounted for several languages is one entry carrying all of them.
    public func discoveredRoots(relativeTo base: URL) -> [CodeArtifact.DiscoveredRoot] {
        var order: [String] = []
        var byKey: [String: CodeArtifact.DiscoveredRoot] = [:]
        for spec in self {
            let path = spec.root.relativePath(from: base)
            let key = "\(path)\u{0}\(spec.detector)"
            guard var existing = byKey[key] else {
                order.append(key)
                byKey[key] = CodeArtifact.DiscoveredRoot(
                    path: path.isEmpty ? "." : path,
                    detector: spec.detector,
                    languages: [spec.language],
                    sourceDirs: spec.sourceDirPaths(relativeTo: base),
                    isFallback: spec.isFallback
                )
                continue
            }
            existing.sourceDirs.append(
                contentsOf: spec.sourceDirPaths(relativeTo: base).filter { !existing.sourceDirs.contains($0) })
            if !existing.languages.contains(spec.language) {
                existing.languages.append(spec.language)
            }
            byKey[key] = existing
        }
        return order.compactMap { byKey[$0] }
    }
}

extension SourceSpec {
    /// This spec's source directories as paths relative to the analysed folder, deduplicated in
    /// discovery order. The folder itself reads as `"."`, matching ``CodeArtifact/DiscoveredRoot``.
    func sourceDirPaths(relativeTo base: URL) -> [String] {
        var seen: Set<String> = []
        return sourceDirs
            .map { $0.relativePath(from: base) }
            .map { $0.isEmpty ? "." : $0 }
            .filter { seen.insert($0).inserted }
    }
}

extension [SourceSpec] {
    /// One spec per language, in first-seen order, so enrichment sees every root of a language at once
    /// and a type in one root still resolves references into another.
    var mergedByLanguage: [SourceSpec] {
        var merged: [SourceSpec] = []
        for spec in self {
            guard let index = merged.firstIndex(where: { $0.language == spec.language }) else {
                merged.append(spec)
                continue
            }
            merged[index] = merged[index].merging(spec)
        }
        return merged
    }
}

extension SourceSpec {
    /// Folds another root of the same language into this one. Every field is named here rather than
    /// mutated in place, so a field added to ``SourceSpec`` later has to say what merging means for
    /// it instead of being dropped from the second root onwards.
    ///
    /// `root`, `detector` and `isFallback` keep the first root's: a merged spec has several roots, and
    /// the full set is recorded separately in `metadata.discoveredRoots`. `diagnostics` from every
    /// root survive the merge, concatenated, so a problem found discovering the second root is never
    /// silently dropped, and so do every root's `nestedRootPaths`.
    func merging(_ other: SourceSpec) -> SourceSpec {
        SourceSpec(
            language: language,
            sourceDirs: sourceDirs + other.sourceDirs,
            root: root,
            detector: detector,
            nestedRootPaths: nestedRootPaths + other.nestedRootPaths,
            diagnostics: diagnostics + other.diagnostics,
            isFallback: isFallback
        )
    }
}
