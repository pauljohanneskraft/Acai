import Foundation

/// A Gradle build or settings script, read as text.
///
/// Gradle scripts are Groovy or Kotlin programs, so this reads only the handful of constructs the
/// detector needs — `include`, `projectDir`, `sourceSets`, `srcDir` — in either DSL's spelling. Both
/// comments and string literals are skipped while searching, so a commented-out `include` names no
/// module and a keyword inside a path names nothing at all.
struct GradleScript {

    private let characters: [Character]

    init(source: String) {
        characters = Array(source)
    }

    private init(characters: [Character]) {
        self.characters = characters
    }

    /// Every single- or double-quoted literal, in order.
    var quotedLiterals: [String] {
        var literals: [String] = []
        var index = 0
        while index < characters.count {
            if let end = commentEnd(at: index) {
                index = end
            } else if let end = stringLiteralEnd(at: index) {
                literals.append(String(characters[(index + 1)..<(end - 1)]))
                index = end
            } else {
                index += 1
            }
        }
        return literals
    }

    /// The remainder of each statement naming `keyword` as a whole word: to the end of its line,
    /// extended across an unclosed `(` so a `include(…)` list spanning lines reads as one statement.
    /// Whole-word matching is what keeps `includeBuild` — a composite build, not a module — out.
    func statements(after keyword: String) -> [GradleScript] {
        scan(for: keyword) { start in
            let end = statementEnd(from: start)
            return (GradleScript(characters: Array(characters[start..<end])), end)
        }
    }

    /// The body of each `name { … }` block, brace-matched.
    func blocks(named name: String) -> [GradleScript] {
        scan(for: name) { start in
            guard let open = braceStart(from: start) else { return nil }
            let end = braceEnd(from: open)
            return (GradleScript(characters: Array(characters[(open + 1)..<end])), end)
        }
    }

    func contains(word: String) -> Bool {
        !statements(after: word).isEmpty
    }

    private func scan(
        for keyword: String,
        _ take: (Int) -> (GradleScript, Int)?
    ) -> [GradleScript] {
        let word = Array(keyword)
        var results: [GradleScript] = []
        var index = 0
        while index < characters.count {
            if let end = skippableEnd(at: index) {
                index = end
            } else if isWholeWord(word, at: index), let (result, next) = take(index + word.count) {
                results.append(result)
                index = max(next, index + word.count)
            } else {
                index += 1
            }
        }
        return results
    }

    private func isWholeWord(_ word: [Character], at index: Int) -> Bool {
        guard index + word.count <= characters.count,
              Array(characters[index..<(index + word.count)]) == word else { return false }
        let leading = index > 0 ? characters[index - 1] : " "
        let trailing = index + word.count < characters.count ? characters[index + word.count] : " "
        return !leading.isGradleIdentifier && !trailing.isGradleIdentifier
    }

    /// The index just past the string literal starting at `index` — nil when none starts there, and
    /// nil for one that is never closed, which leaves the quote to be read as ordinary text.
    private func stringLiteralEnd(at index: Int) -> Int? {
        let quote = characters[index]
        guard quote == "\"" || quote == "'" else { return nil }
        var cursor = index + 1
        while cursor < characters.count {
            if characters[cursor] == "\\" {
                cursor += 2
                continue
            }
            if characters[cursor] == quote {
                return cursor + 1
            }
            cursor += 1
        }
        return nil
    }

    private func commentEnd(at index: Int) -> Int? {
        guard characters[index] == "/", index + 1 < characters.count else { return nil }
        switch characters[index + 1] {
        case "/":
            return characters[(index + 1)...].firstIndex(of: "\n") ?? characters.count
        case "*":
            return blockCommentEnd(from: index + 2)
        default:
            return nil
        }
    }

    private func blockCommentEnd(from start: Int) -> Int {
        var cursor = start
        while cursor + 1 < characters.count {
            if characters[cursor] == "*", characters[cursor + 1] == "/" {
                return cursor + 2
            }
            cursor += 1
        }
        return characters.count
    }

    private func statementEnd(from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < characters.count {
            if let end = skippableEnd(at: index) {
                index = end
                continue
            }
            depth += characters[index].parenthesisNesting
            if depth <= 0, characters[index].endsGradleStatement { return index }
            index += 1
        }
        return characters.count
    }

    /// The `{` opening a block after `start`. Only whitespace may come first, so `sourceSets` named in
    /// an expression rather than opening a block is passed over.
    private func braceStart(from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if let end = commentEnd(at: index) {
                index = end
                continue
            }
            guard characters[index] != "{" else { return index }
            guard characters[index].isWhitespace else { return nil }
            index += 1
        }
        return nil
    }

    private func braceEnd(from openBrace: Int) -> Int {
        var depth = 0
        var index = openBrace
        while index < characters.count {
            if let end = skippableEnd(at: index) {
                index = end
                continue
            }
            depth += characters[index].braceNesting
            if depth == 0, characters[index] == "}" { return index }
            index += 1
        }
        return characters.count
    }

    /// The index just past whatever must be stepped over rather than read at `index` — a comment or a
    /// string literal — or nil when ordinary code starts there.
    private func skippableEnd(at index: Int) -> Int? {
        commentEnd(at: index) ?? stringLiteralEnd(at: index)
    }
}

private extension Character {

    var isGradleIdentifier: Bool { isLetter || isNumber || self == "_" }

    var endsGradleStatement: Bool { self == "\n" || self == ";" }

    var parenthesisNesting: Int {
        nesting(opening: "(", closing: ")")
    }

    var braceNesting: Int {
        nesting(opening: "{", closing: "}")
    }

    private func nesting(opening: Character, closing: Character) -> Int {
        switch self {
        case opening:
            1
        case closing:
            -1
        default:
            0
        }
    }
}
