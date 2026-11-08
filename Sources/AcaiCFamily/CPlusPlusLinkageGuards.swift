/// Blanks the `#ifdef __cplusplus … #endif` guards that wrap nothing but an `extern "C"` linkage
/// specification's opening `extern "C" {` or its closing `}`.
///
/// Tree-sitter cannot balance a brace whose partner lives in another preprocessor branch, so the
/// near-universal C header guard parses as a missing `}`. Each qualifying guard becomes spaces of
/// the same length with its newlines kept, which drops both braces while leaving every byte offset
/// and line/column position in the file exactly where it was.
///
/// A guard holding anything else — a real C++-only declaration — is left alone.
struct CPlusPlusLinkageGuards {
    let source: String

    private let conditions: Set<String> = [
        "#ifdef__cplusplus", "#ifdefined(__cplusplus)", "#ifdefined__cplusplus"
    ]
    private let linkageBodies: Set<String> = ["extern\"C\"{", "}"]
    private let maximumBodyLines = 3

    var neutralized: String {
        let lines = lineRanges
        var guards: [Range<String.Index>] = []
        var index = 0
        while index < lines.count {
            guard let content = codeContent(of: source[lines[index]]),
                  conditions.contains(compacted(content)),
                  let end = linkageGuardEnd(after: index, in: lines) else {
                index += 1
                continue
            }
            guards.append(lines[index].lowerBound..<lines[end].upperBound)
            index = end + 1
        }
        return guards.isEmpty ? source : blanking(guards)
    }

    /// The index of the `#endif` closing the guard opened at `start`, when everything between the
    /// two is one of the linkage specification's braces and nothing else.
    private func linkageGuardEnd(after start: Int, in lines: [Range<String.Index>]) -> Int? {
        var body = ""
        var index = start + 1
        while index < lines.count, index - start <= maximumBodyLines + 1 {
            guard let content = codeContent(of: source[lines[index]]) else { return nil }
            let compact = compacted(content)
            if compact == "#endif" { return linkageBodies.contains(body) ? index : nil }
            if compact.hasPrefix("#") { return nil }
            body += compact
            index += 1
        }
        return nil
    }

    private func blanking(_ ranges: [Range<String.Index>]) -> String {
        var result = ""
        result.reserveCapacity(source.count)
        var cursor = source.startIndex
        for range in ranges {
            result += source[cursor..<range.lowerBound]
            result += source[range].map { $0 == "\n" ? "\n" : " " }
            cursor = range.upperBound
        }
        result += source[cursor...]
        return result
    }

    /// `line` without its comments, or `nil` when it opens a block comment it does not close — a
    /// shape this matcher declines to reason about rather than guess at.
    private func codeContent(of line: Substring) -> String? {
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(after: index)
            guard line[index] == "/", next < line.endIndex else {
                result.append(line[index])
                index = next
                continue
            }
            if line[next] == "/" { return result }
            guard line[next] == "*" else {
                result.append(line[index])
                index = next
                continue
            }
            guard let close = line.range(of: "*/", range: next..<line.endIndex) else { return nil }
            result.append(" ")
            index = close.upperBound
        }
        return result
    }

    private func compacted(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private var lineRanges: [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = source.startIndex
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "\n" {
                ranges.append(lineStart..<index)
                lineStart = source.index(after: index)
            }
            index = source.index(after: index)
        }
        if lineStart < source.endIndex { ranges.append(lineStart..<source.endIndex) }
        return ranges
    }
}
