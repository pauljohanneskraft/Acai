import Foundation

/// A `tsconfig.json` is JSONC, not JSON: `tsc` accepts `//` and `/* … */` comments and a trailing
/// comma before a closing brace or bracket, and the file `tsc --init` writes is full of both.
/// `JSONSerialization` rejects all of it, so the text is reduced to strict JSON first.
struct JSONWithComments {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    /// Nil when the file is missing or is not UTF-8 — as distinct from present but unparseable,
    /// which is ``object`` returning nil.
    init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        self.text = text
    }

    /// The document's top-level object, or nil when what remains is not one.
    var object: [String: Any]? {
        guard let data = strictJSON.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The same document with comments blanked out and trailing commas dropped. String literals are
    /// consumed whole, so a `//` or a `,}` inside one is left alone.
    var strictJSON: String {
        var output: [Character] = []
        output.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            switch text[index] {
            case "\"":
                let end = endOfString(from: index)
                output.append(contentsOf: text[index..<end])
                index = end
            case "/" where isCommentStart(at: index):
                index = endOfComment(from: index)
                output.append(" ")
            case "}", "]":
                dropTrailingComma(from: &output)
                output.append(text[index])
                index = text.index(after: index)
            default:
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return String(output)
    }

    /// The index just past the closing quote of the string literal opening at `start`.
    private func endOfString(from start: String.Index) -> String.Index {
        var index = text.index(after: start)
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if text[index] == "\"" { return text.index(after: index) }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private func isCommentStart(at index: String.Index) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return false }
        return text[next] == "/" || text[next] == "*"
    }

    /// The index just past the comment opening at `start`. A line comment ends *at* its newline, so
    /// the line structure survives.
    private func endOfComment(from start: String.Index) -> String.Index {
        let isLineComment = text[text.index(after: start)] == "/"
        var index = text.index(start, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
        while index < text.endIndex {
            if isLineComment {
                if text[index].isNewline { return index }
            } else if text[index] == "*" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" { return text.index(after: next) }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private func dropTrailingComma(from output: inout [Character]) {
        var index = output.count - 1
        while index >= 0, output[index].isWhitespace {
            index -= 1
        }
        guard index >= 0, output[index] == "," else { return }
        output.remove(at: index)
    }
}
