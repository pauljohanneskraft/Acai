import AcaiCore
import Foundation

/// The churn × complexity join behind the "hotspot" technique (Michael Feathers, *Your Code as a
/// Crime Scene*): one entry per file, churn (commits touching it) against complexity
/// (`CodeMetrics.TypeMetric.maxCyclomaticComplexity`, maxed across the file's declared types). The
/// top-right quadrant — above both medians — is the ranked hotspot list.
///
/// Agnostic and git-free: churn arrives as an already-walked map, so the same scoring serves the
/// app's scatter chart, `acai hotspots` and `acai_hotspots`.
public struct Hotspots: Sendable, Equatable, Codable {
    public struct File: Sendable, Equatable, Codable, Identifiable {
        public let path: String
        public let churn: Int
        public let complexity: Int
        /// Churn × complexity — the ranking the top-right quadrant is ordered by.
        public let score: Int
        /// Above both medians. A carried flag rather than something a presentation re-derives, so a
        /// scatter plot can state it in text and in an accessibility value instead of by colour.
        public let isHotspot: Bool

        public var id: String { path }
        public var fileName: String { path.split(separator: "/").last.map(String.init) ?? path }
    }

    public let files: [File]
    public let churnThreshold: Double
    public let complexityThreshold: Double

    /// The hotspots alone, highest score first; ties break on path so a report is reproducible.
    public var ranked: [File] {
        files.filter(\.isHotspot).sorted { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
    }

    /// Joins two already-resolved per-file maps, keyed by paths relative to the same root.
    public init(complexityByFile: [String: Int], churnByFile: [String: Int]) {
        let paths = Set(complexityByFile.keys).union(churnByFile.keys)
        let churnMedian = churnByFile.values.map(Double.init).median
        let complexityMedian = complexityByFile.values.map(Double.init).median
        churnThreshold = churnMedian
        complexityThreshold = complexityMedian
        files = paths.map { path in
            let churn = churnByFile[path] ?? 0
            let complexity = complexityByFile[path] ?? 0
            return File(
                path: path,
                churn: churn,
                complexity: complexity,
                score: churn * complexity,
                isHotspot: Double(churn) > churnMedian && Double(complexity) > complexityMedian
            )
        }.sorted { $0.path < $1.path }
    }

    /// Computes per-file complexity (max across a file's declared types, mirroring
    /// `maxCyclomaticComplexity`'s own "max" semantics) from an already-enriched artifact, then
    /// joins it against an already-walked churn map. `computeMetrics()` walks the whole artifact,
    /// so call this once rather than per render.
    public init(artifact: CodeArtifact, churnByFile: [String: Int]) {
        let metrics = artifact.computeMetrics()
        let complexityByID = Dictionary(
            metrics.types.map { ($0.id, $0.maxCyclomaticComplexity) }, uniquingKeysWith: max)
        var complexityByFile: [String: Int] = [:]
        for type in artifact.flattened() {
            guard let path = type.location?.filePath, let complexity = complexityByID[type.id] else { continue }
            complexityByFile[path] = max(complexityByFile[path, default: 0], complexity)
        }
        self.init(complexityByFile: complexityByFile, churnByFile: churnByFile)
    }
}

extension Array where Element == Double {
    /// The middle value of the sorted array (average of the two middle values when the count is
    /// even), `0` when empty — a median rather than a mean because the quadrant thresholds must
    /// survive a handful of extreme outliers.
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
