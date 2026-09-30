/// A `[…]` character class from a `.gitignore` pattern, stored as ranges rather than the expanded
/// set so `[\u{0}-\u{10FFFF}]` costs one range rather than a million members.
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

/// Reading a `[…]` out of a pattern: the compiled class when it is well formed, the index just past
/// what was consumed, and any problems worth reporting.
///
/// Parsing is total. A class git would reject — an unterminated bracket, an inverted range — yields
/// no class and a problem describing it, and the caller falls back to matching a literal `[`, which
/// is what git itself does with an unterminated bracket.
struct GitignoreCharacterClassParse: Sendable {

    let characters: GitignoreCharacterClass?
    let endIndex: Int
    let problems: [String]

    init(pattern: [Character], openingBracket: Int) {
        var index = openingBracket + 1
        var isNegated = false
        if index < pattern.count, pattern[index] == "!" || pattern[index] == "^" {
            isNegated = true
            index += 1
        }
        let body = GitignoreCharacterClassBody(pattern: pattern, start: index)
        guard body.isClosed, body.problems.isEmpty else {
            characters = nil
            endIndex = openingBracket + 1
            problems = body.problems.isEmpty ? ["`[` is never closed"] : body.problems
            return
        }
        characters = GitignoreCharacterClass(ranges: body.ranges, isNegated: isNegated)
        endIndex = body.endIndex + 1
        problems = []
    }
}

/// The characters between a `[` and its `]`, read as ranges.
private struct GitignoreCharacterClassBody {
    let ranges: [ClosedRange<Character>]
    let problems: [String]
    /// The index the scan stopped at: the closing `]` when there is one.
    let endIndex: Int
    let isClosed: Bool

    init(pattern: [Character], start: Int) {
        var index = start
        var ranges: [ClosedRange<Character>] = []
        var problems: [String] = []
        // A `]` in the first position is a literal, matching shell-glob convention.
        var isFirst = true
        while index < pattern.count, pattern[index] != "]" || isFirst {
            isFirst = false
            let element = GitignoreCharacterClassElement(pattern: pattern, index: index)
            if let range = element.range { ranges.append(range) }
            if let problem = element.problem { problems.append(problem) }
            index = element.endIndex
            if ranges.count > GitignoreCharacterClass.maximumRanges {
                problems.append("character class has more than \(GitignoreCharacterClass.maximumRanges) ranges")
                break
            }
        }
        self.ranges = ranges
        self.problems = problems
        endIndex = index
        isClosed = index < pattern.count && pattern[index] == "]"
    }
}

/// One entry inside a `[…]`: a single character, or a range written `a-z`.
private struct GitignoreCharacterClassElement {
    let range: ClosedRange<Character>?
    let problem: String?
    let endIndex: Int

    init(pattern: [Character], index: Int) {
        let lower = pattern[index]
        guard index + 2 < pattern.count, pattern[index + 1] == "-", pattern[index + 2] != "]" else {
            range = lower...lower
            problem = nil
            endIndex = index + 1
            return
        }
        let upper = pattern[index + 2]
        let isOrdered = lower <= upper
        range = isOrdered ? lower...upper : nil
        problem = isOrdered ? nil : "character range [\(lower)-\(upper)] runs backwards"
        endIndex = index + 3
    }
}
