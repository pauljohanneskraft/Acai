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
                    languages: [spec.language]
                )
                continue
            }
            guard !existing.languages.contains(spec.language) else { continue }
            existing.languages.append(spec.language)
            byKey[key] = existing
        }
        return order.compactMap { byKey[$0] }
    }
}
