/// Blanks paired `#ifdef __cplusplus` guards around `extern "C" {` and `}`, keeping UTF-16 width and lines.
struct CPlusPlusLinkageGuards {
    let source: String

    private let conditions: Set<String> = [
        "#ifdef__cplusplus", "#ifdefined(__cplusplus)", "#ifdefined__cplusplus"
    ]
    private let opener = "extern\"C\"{"
    private let closer = "}"
    private let maximumBodyLines = 3

    var neutralized: String {
        let lines = lineRanges
        var openGuards: [Range<String.Index>] = []
        var pairedGuards: [Range<String.Index>] = []
        var index = 0
        while index < lines.count {
            guard let content = codeContent(of: source[lines[index]]),
                  conditions.contains(compacted(content)),
                  let (end, body) = guardBody(after: index, in: lines) else {
                index += 1
                continue
            }
            let range = lines[index].lowerBound..<lines[end].upperBound
            if body == opener {
                openGuards.append(range)
            } else if let open = openGuards.popLast() {
                pairedGuards += [open, range]
            }
            index = end + 1
        }
        return pairedGuards.isEmpty ? source : blanking(pairedGuards.sorted { $0.lowerBound < $1.lowerBound })
    }

    private func guardBody(after start: Int, in lines: [Range<String.Index>]) -> (end: Int, body: String)? {
        var body = ""
        var index = start + 1
        while index < lines.count, index <= start + maximumBodyLines + 1 {
            guard let content = codeContent(of: source[lines[index]]) else { return nil }
            let compact = compacted(content)
            if compact == "#endif" { return body == opener || body == closer ? (index, body) : nil }
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
            for character in source[range] {
                if character.isNewline {
                    result.append(character)
                } else {
                    result.append(String(repeating: " ", count: character.utf16.count))
                }
            }
            cursor = range.upperBound
        }
        result += source[cursor...]
        return result
    }

    /// `nil` when the line opens a block comment it does not close.
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
            if source[index].isNewline {
                ranges.append(lineStart..<index)
                lineStart = source.index(after: index)
            }
            index = source.index(after: index)
        }
        if lineStart < source.endIndex { ranges.append(lineStart..<source.endIndex) }
        return ranges
    }
}
