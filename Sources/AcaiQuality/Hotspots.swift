import AcaiCore
import Foundation

/// Churn × complexity per file; the files above both medians are the hotspots.
public struct Hotspots: Sendable, Equatable, Codable {
    public struct File: Sendable, Equatable, Codable, Identifiable {
        public let path: String
        /// The declared type whose most complex method sets `complexity`; `nil` for a file with none.
        public let type: String?
        public let churn: Int
        public let complexity: Int
        public let score: Int
        public let isHotspot: Bool

        public var id: String { path }
        public var fileName: String { path.split(separator: "/").last.map(String.init) ?? path }
    }

    /// The ranked list `acai hotspots` and `acai_hotspots` both emit.
    public struct Report: Sendable, Equatable, Codable {
        public let churnThreshold: Double
        public let complexityThreshold: Double
        public let commitWindow: Int
        public let filesScored: Int
        /// Every file above both medians, even when `top` keeps fewer.
        public let hotspotCount: Int
        public let hotspots: [File]

        public init(hotspots: Hotspots, commitWindow: Int, top: Int?) {
            churnThreshold = hotspots.churnThreshold
            complexityThreshold = hotspots.complexityThreshold
            self.commitWindow = commitWindow
            filesScored = hotspots.files.count
            let ranked = hotspots.ranked
            hotspotCount = ranked.count
            self.hotspots = top.map { Array(ranked.prefix($0)) } ?? ranked
        }
    }

    public let files: [File]
    public let churnThreshold: Double
    public let complexityThreshold: Double

    public var ranked: [File] {
        files.filter(\.isHotspot).sorted { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
    }

    public init(complexityByFile: [String: Int], churnByFile: [String: Int], typeByFile: [String: String] = [:]) {
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
                type: typeByFile[path],
                churn: churn,
                complexity: complexity,
                score: churn * complexity,
                isHotspot: Double(churn) > churnMedian && Double(complexity) > complexityMedian
            )
        }.sorted { $0.path < $1.path }
    }

    /// Runs `computeMetrics()` over the whole artifact, so build it once rather than per render.
    public init(artifact: CodeArtifact, churnByFile: [String: Int]) {
        let metrics = artifact.computeMetrics()
        let complexityByID = Dictionary(
            metrics.types.map { ($0.id, $0.maxCyclomaticComplexity) }, uniquingKeysWith: max)
        var mostComplexByFile: [String: (type: String, complexity: Int)] = [:]
        for type in artifact.flattened() {
            guard let path = type.location?.filePath, let complexity = complexityByID[type.id] else { continue }
            let candidate = (type: type.qualifiedName, complexity: complexity)
            guard let current = mostComplexByFile[path] else {
                mostComplexByFile[path] = candidate
                continue
            }
            if candidate.complexity > current.complexity
                || (candidate.complexity == current.complexity && candidate.type < current.type) {
                mostComplexByFile[path] = candidate
            }
        }
        self.init(
            complexityByFile: mostComplexByFile.mapValues { $0.complexity },
            churnByFile: churnByFile,
            typeByFile: mostComplexByFile.mapValues { $0.type }
        )
    }
}

extension Array where Element == Double {
    /// `0` when empty; a median so the quadrant thresholds survive a few extreme outliers.
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
