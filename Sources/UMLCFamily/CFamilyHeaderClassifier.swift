/// Decides whether an ambiguous `.h` header is C or C++.
///
/// `.h` is shared by both languages, but the engine routes each extension to exactly one parser, so
/// the C parser owns `.h` and consults this classifier to pick the right grammar+extractor per file.
/// The scan is deliberately conservative — it strips comments and string/char literals first, then
/// looks only for *structural* C++ markers, so a C header that merely mentions "class" in a comment
/// is not misrouted.
struct CFamilyHeaderClassifier {
    let source: String

    init(source: String) {
        self.source = source
    }

    /// `true` when the header contains a construct that is valid C++ but not C.
    var looksLikeCpp: Bool {
        let code = strippedCode

        // The scope-resolution operator is the single strongest, most common C++-only token.
        if code.contains("::") { return true }

        let keywordMarkers = [
            "class", "namespace", "template", "virtual", "nullptr", "constexpr",
            "noexcept", "typename", "operator", "explicit", "concept", "co_await"
        ]
        if keywordMarkers.contains(where: { containsWord($0, in: code) }) { return true }

        // `public:` / `private:` / `protected:` access-section labels.
        if ["public", "private", "protected"].contains(where: { containsAccessLabel($0, in: code) }) {
            return true
        }

        return code.contains("extern \"C++\"")
    }

    // MARK: - Helpers

    /// Whether `word` appears as a whole identifier token (not a substring of a longer name).
    private func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || !Self.isIdentifierChar(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex
                || !Self.isIdentifierChar(text[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    /// Whether `label` appears as an access-section label: `label` followed (ignoring spaces) by a
    /// single `:` that is not part of a `::`.
    private func containsAccessLabel(_ label: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: label, range: searchStart..<text.endIndex) {
            searchStart = range.upperBound
            let beforeOK = range.lowerBound == text.startIndex
                || !Self.isIdentifierChar(text[text.index(before: range.lowerBound)])
            guard beforeOK else { continue }
            var index = range.upperBound
            while index < text.endIndex, text[index] == " " || text[index] == "\t" {
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == ":" else { continue }
            let next = text.index(after: index)
            if next == text.endIndex || text[next] != ":" { return true }
        }
        return false
    }

    private static func isIdentifierChar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The source with line/block comments and string/char literals removed, so keyword scanning
    /// sees only code.
    private var strippedCode: String {
        enum State { case code, lineComment, blockComment, string, char }
        var state: State = .code
        var output = ""
        output.reserveCapacity(source.count)
        var iterator = source.makeIterator()
        var pending: Character? = iterator.next()

        func advance() -> Character? {
            let current = pending
            pending = iterator.next()
            return current
        }

        while let character = advance() {
            switch state {
            case .code:
                if character == "/", pending == "/" {
                    state = .lineComment
                    _ = advance()
                } else if character == "/", pending == "*" {
                    state = .blockComment
                    _ = advance()
                } else if character == "\"" {
                    state = .string
                    output.append(" ")
                } else if character == "'" {
                    state = .char
                    output.append(" ")
                } else {
                    output.append(character)
                }
            case .lineComment:
                if character == "\n" {
                    state = .code
                    output.append("\n")
                }
            case .blockComment:
                if character == "*", pending == "/" {
                    state = .code
                    _ = advance()
                    output.append(" ")
                }
            case .string:
                if character == "\\" {
                    _ = advance()
                } else if character == "\"" {
                    state = .code
                }
            case .char:
                if character == "\\" {
                    _ = advance()
                } else if character == "'" {
                    state = .code
                }
            }
        }
        return output
    }
}
