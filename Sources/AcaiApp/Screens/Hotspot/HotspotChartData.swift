import AcaiCore
import Foundation

/// Chart-ready data for the churn × complexity scatter (the classic "hotspot" technique —
/// Michael Feathers, *Your Code as a Crime Scene*): one point per file, churn (commits touching it)
/// on one axis, complexity (`CodeMetrics.TypeMetric.maxCyclomaticComplexity`, maxed across the
/// file's declared types) on the other. The top-right quadrant — above both medians — is the
/// hotspot list: files that are simultaneously complex *and* frequently changed.
struct HotspotChartData {
    /// One file's plotted point. `isHotspot` is the required non-color signal alongside `Charts`'
    /// categorical `.symbol(by:)` shape: a hotspot's status is also stated in the ranked list and
    /// each point's accessibility value, never conveyed by color alone.
    struct Point: Identifiable, Equatable {
        let id: String
        let fileName: String
        let churn: Int
        let complexity: Int
        let isHotspot: Bool
    }

    let points: [Point]
    let churnThreshold: Double
    let complexityThreshold: Double

    var hotspots: [Point] {
        points.filter(\.isHotspot).sorted { $0.churn * $0.complexity > $1.churn * $1.complexity }
    }

    /// Low-level, directly testable initializer: joins two already-resolved per-file maps. Kept
    /// separate from the `CodeArtifact`-based convenience initializer below so the churn/complexity
    /// join and quadrant-threshold logic can be unit-tested without a real artifact or git fixture.
    init(complexityByFile: [String: Int], churnByFile: [String: Int]) {
        let files = Set(complexityByFile.keys).union(churnByFile.keys)
        let churnMedian = churnByFile.values.map(Double.init).median
        let complexityMedian = complexityByFile.values.map(Double.init).median
        churnThreshold = churnMedian
        complexityThreshold = complexityMedian
        points = files.map { path in
            let churn = churnByFile[path] ?? 0
            let complexity = complexityByFile[path] ?? 0
            return Point(
                id: path,
                fileName: (path as NSString).lastPathComponent,
                churn: churn,
                complexity: complexity,
                isHotspot: Double(churn) > churnMedian && Double(complexity) > complexityMedian
            )
        }.sorted { $0.id < $1.id }
    }

    /// Convenience initializer: computes per-file complexity (max across a file's declared types,
    /// mirroring `maxCyclomaticComplexity`'s own "max" semantics) from an already-enriched artifact,
    /// then joins it against an already-walked churn map. Call once (e.g. from a view's `init` or a
    /// `.task`, never from a view's `body`) — `computeMetrics()` walks the whole artifact.
    init(artifact: CodeArtifact, churnByFile: [String: Int]) {
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
    /// even), `0` when empty — used for the hotspot scatter's quadrant thresholds since a median is
    /// more robust to outliers than a mean would be. A computed property on the array itself, not a
    /// static helper function.
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
