/// The distinct physical source lines a set of declaration extents covers.
///
/// Overlapping extents are merged per file, which is what makes a lines-of-code total trustworthy:
/// a nested type sits inside its enclosing declaration's extent, and a type's members sit inside
/// their own declaration's, so a naive sum would count the same lines several times.
public struct LineSpanUnion: Equatable, Sendable {
    private var files: [String: FileLines] = [:]

    public init() {}

    /// Records `location`'s extent. Ignored when the location is absent or carries no ``endLine``,
    /// so an unmeasured declaration contributes nothing rather than a phantom single line.
    public mutating func add(_ location: SourceLocation?) {
        guard let location, let span = location.lineSpan else { return }
        files[location.filePath, default: FileLines()].add(location.line...(location.line + span - 1))
    }

    public mutating func formUnion(_ other: LineSpanUnion) {
        for (path, lines) in other.files {
            files[path, default: FileLines()].formUnion(lines)
        }
    }

    /// Distinct lines covered across every file, `0` when nothing measurable was recorded.
    public var lineCount: Int {
        files.values.reduce(0) { $0 + $1.count }
    }

    /// Distinct lines covered, keyed by whatever `group` derives from each file's path — how a
    /// per-module total attributes each extent to the module of the file it was written in rather
    /// than the module of the type it belongs to (a cross-module extension is declared elsewhere).
    ///
    /// One pass over the files, not one per group: two files never share a line, so a group's total
    /// is simply the sum of its files'.
    public func lineCounts(groupedBy group: (String) -> String) -> [String: Int] {
        var totals: [String: Int] = [:]
        for (path, lines) in files { totals[group(path), default: 0] += lines.count }
        return totals
    }

    /// The extents recorded within one file, merged on read so overlapping declarations count once.
    private struct FileLines: Equatable {
        private var ranges: [ClosedRange<Int>] = []

        mutating func add(_ range: ClosedRange<Int>) {
            ranges.append(range)
        }

        mutating func formUnion(_ other: FileLines) {
            ranges.append(contentsOf: other.ranges)
        }

        var count: Int {
            var total = 0
            var highestCounted: Int?
            for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                let start = highestCounted.map { Swift.max(range.lowerBound, $0 + 1) } ?? range.lowerBound
                if start <= range.upperBound { total += range.upperBound - start + 1 }
                highestCounted = Swift.max(highestCounted ?? range.upperBound, range.upperBound)
            }
            return total
        }
    }
}
