/// A `[…]` character class from a `.gitignore` pattern, stored as ranges rather than the expanded
/// set so `[\u{0}-\u{10FFFF}]` costs one range rather than a million members.
///
/// Parsing is total: a class git would reject — an unterminated bracket, an inverted range — yields
/// no class and a problem describing it, and the caller falls back to matching a literal `[`, which
/// is what git itself does with an unterminated bracket.
struct GitignoreCharacterClass: Sendable {

    /// A class with more ranges than this is refused rather than compiled, so a pattern from an
    /// analyzed repository cannot make matching arbitrarily expensive.
    static let maximumRanges = 256

    let ranges: [ClosedRange<Character>]
    let isNegated: Bool

    func contains(_ character: Character) -> Bool {
        isNegated != ranges.contains { $0.contains(character) }
    }
}

extension GitignoreCharacterClass {
    /// The outcome of reading a `[…]` out of `pattern` starting at `openingBracket`: the compiled
    /// class when it is well formed, the index just past what was consumed, and any problems worth
    /// reporting.
    struct Parse: Sendable {
        let characters: GitignoreCharacterClass?
        let endIndex: Int
        let problems: [String]
    }
}

extension GitignoreCharacterClass.Parse {
    init(pattern: [Character], openingBracket: Int) {
        var index = openingBracket + 1
        var isNegated = false
        if index < pattern.count, pattern[index] == "!" || pattern[index] == "^" {
            isNegated = true
            index += 1
        }
        var ranges: [ClosedRange<Character>] = []
        var problems: [String] = []
        // A `]` in the first position is a literal, matching shell-glob convention.
        var isFirst = true
        while index < pattern.count, pattern[index] != "]" || isFirst {
            isFirst = false
            let lower = pattern[index]
            if index + 2 < pattern.count, pattern[index + 1] == "-", pattern[index + 2] != "]" {
                let upper = pattern[index + 2]
                if lower <= upper {
                    ranges.append(lower...upper)
                } else {
                    problems.append("character range [\(lower)-\(upper)] runs backwards")
                }
                index += 3
            } else {
                ranges.append(lower...lower)
                index += 1
            }
            if ranges.count > GitignoreCharacterClass.maximumRanges {
                problems.append("character class has more than \(GitignoreCharacterClass.maximumRanges) ranges")
                self.init(characters: nil, endIndex: openingBracket + 1, problems: problems)
                return
            }
        }
        guard index < pattern.count else {
            problems.append("`[` is never closed")
            self.init(characters: nil, endIndex: openingBracket + 1, problems: problems)
            return
        }
        guard problems.isEmpty else {
            self.init(characters: nil, endIndex: openingBracket + 1, problems: problems)
            return
        }
        self.init(
            characters: GitignoreCharacterClass(ranges: ranges, isNegated: isNegated),
            endIndex: index + 1,
            problems: problems
        )
    }
}
