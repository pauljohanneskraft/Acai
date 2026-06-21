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
        let scan = scanned
        let code = scan.stripped

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

        // The `extern "C++"` linkage specification is itself a string literal, so it can only be
        // seen in the string-preserving view. A C string whose *contents* spell `extern "C++"`
        // must escape its inner quotes (`"extern \"C++\""`), which breaks this substring — so only
        // a real (unescaped) linkage specification matches.
        return scan.codePreservingStrings.contains("extern \"C++\"")
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

    /// Two comment-free views of the source, produced in one pass:
    /// - `stripped`: comments **and** string/char literals removed, so keyword scanning sees only
    ///   structural code (a C++ marker named inside a string never misroutes the header).
    /// - `codePreservingStrings`: comments removed but string/char literals kept verbatim — the
    ///   only view in which the `extern "C++"` linkage specification (itself a string literal) is
    ///   visible.
    private var scanned: (stripped: String, codePreservingStrings: String) {
        enum State { case code, lineComment, blockComment, string, char }
        var state: State = .code
        var stripped = ""
        var withStrings = ""
        stripped.reserveCapacity(source.count)
        withStrings.reserveCapacity(source.count)
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
                    stripped.append(" ")
                    withStrings.append(character)
                } else if character == "'" {
                    state = .char
                    stripped.append(" ")
                    withStrings.append(character)
                } else {
                    stripped.append(character)
                    withStrings.append(character)
                }
            case .lineComment:
                if character == "\n" {
                    state = .code
                    stripped.append("\n")
                    withStrings.append("\n")
                }
            case .blockComment:
                if character == "*", pending == "/" {
                    state = .code
                    _ = advance()
                    stripped.append(" ")
                    withStrings.append(" ")
                }
            case .string:
                // Keep the literal verbatim (incl. escapes) in `withStrings`; `stripped` gets nothing.
                if character == "\\" {
                    withStrings.append(character)
                    if let escaped = advance() { withStrings.append(escaped) }
                } else if character == "\"" {
                    withStrings.append(character)
                    state = .code
                } else {
                    withStrings.append(character)
                }
            case .char:
                if character == "\\" {
                    withStrings.append(character)
                    if let escaped = advance() { withStrings.append(escaped) }
                } else if character == "'" {
                    withStrings.append(character)
                    state = .code
                } else {
                    withStrings.append(character)
                }
            }
        }
        return (stripped, withStrings)
    }
}
