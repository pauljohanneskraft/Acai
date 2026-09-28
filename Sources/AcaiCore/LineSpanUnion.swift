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

    /// Distinct lines covered in the files `predicate` accepts — how a per-module total attributes
    /// each extent to the module of the file it was written in, not the module of the type it
    /// belongs to (a cross-module extension is declared elsewhere).
    public func lineCount(inFilesWhere predicate: (String) -> Bool) -> Int {
        files.filter { predicate($0.key) }.values.reduce(0) { $0 + $1.count }
    }

    /// Every file an extent was recorded in.
    public var filePaths: [String] { Array(files.keys) }

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
