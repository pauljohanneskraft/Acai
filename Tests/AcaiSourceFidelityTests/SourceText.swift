import Foundation

/// A source file addressed the way `SourceLocation` addresses it: 1-based lines, and 1-based
/// columns counted in `Character`s.
struct SourceText {
    let lines: [String]

    init(_ source: String) {
        lines = source.components(separatedBy: "\n")
    }

    var lineCount: Int { lines.count }

    func line(_ number: Int) -> String? {
        guard number >= 1, number <= lines.count else { return nil }
        return lines[number - 1]
    }

    func character(line number: Int, column: Int) -> Character? {
        guard let text = line(number) else { return nil }
        let characters = Array(text)
        guard column >= 1, column <= characters.count else { return nil }
        return characters[column - 1]
    }

    /// The text of lines `first` through `last` inclusive, clamped to the file.
    func span(from first: Int, through last: Int) -> String {
        let lower = max(first, 1)
        let upper = min(max(last, first), lines.count)
        guard lower <= lines.count, lower <= upper else { return "" }
        return lines[(lower - 1)...(upper - 1)].joined(separator: "\n")
    }
}

/// Finds a needle in a haystack while ignoring the haystack's whitespace, so a type written
/// `Map<String, int>` is found by the spelling `Map<String,int>` without the search having to guess
/// where a language puts its spaces.
struct WhitespaceInsensitiveSearch {
    let characters: [Character]

    init(_ haystack: String) {
        characters = Array(haystack)
    }

    /// Where one match sits in the haystack, and what follows it.
    struct Match: Sendable {
        let start: Int
        /// One past the last matched character.
        let end: Int
        /// The first non-whitespace character after the match, `nil` at the end of the haystack.
        let following: Character?
        /// Whether the character before the match can continue an identifier, which would make this
        /// a match on the tail of a longer word.
        let isPrecededByWord: Bool
    }

    func matches(of needle: String) -> [Match] {
        let wanted = needle.filter { !$0.isWhitespace }
        guard !wanted.isEmpty else { return [] }
        return characters.indices.compactMap { start in
            guard !characters[start].isWhitespace else { return nil }
            guard let end = endOfMatch(of: Array(wanted), from: start) else { return nil }
            return Match(
                start: start,
                end: end,
                following: characters[end...].first { !$0.isWhitespace },
                isPrecededByWord: start > 0 && characters[start - 1].continuesIdentifier
            )
        }
    }

    private func endOfMatch(of wanted: [Character], from start: Int) -> Int? {
        var index = start
        for character in wanted {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count, characters[index] == character else { return nil }
            index += 1
        }
        return index
    }
}

extension Character {
    /// Whether this character can appear inside an identifier in any language the suite covers.
    var continuesIdentifier: Bool {
        isLetter || isNumber || self == "_" || self == "$"
    }
}
