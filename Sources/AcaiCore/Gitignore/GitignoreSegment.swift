/// The wildcard vocabulary git allows *within* one path component: `*`, `?`, and a `[…]` character
/// class. A segment never matches a `/`, which falls out of matching one component at a time.
///
/// Matching is bounded: the loop remembers a single `*` to fall back to, so a pattern of length `m`
/// against a component of length `n` costs `O(n · m)` however many wildcards it carries. A
/// backtracking regex would not give that guarantee, and these patterns come from a file in the
/// analyzed repository — external input.
struct GitignoreSegment: Sendable {

    enum Token: Sendable {
        case literal(Character)
        case anyCharacter
        case anyRun
        case characterClass(GitignoreCharacterClass)

        func matches(_ character: Character) -> Bool {
            switch self {
            case .literal(let expected): expected == character
            case .anyCharacter: true
            case .anyRun: false
            case .characterClass(let characters): characters.contains(character)
            }
        }
    }

    let tokens: [Token]
    let problems: [String]

    init(pattern: [Character]) {
        var tokens: [Token] = []
        var problems: [String] = []
        var index = 0
        while index < pattern.count {
            switch pattern[index] {
            case "*":
                if !tokens.last.isAnyRun { tokens.append(.anyRun) }
                index += 1
            case "?":
                tokens.append(.anyCharacter)
                index += 1
            case "[":
                let parsed = GitignoreCharacterClass.Parse(pattern: pattern, openingBracket: index)
                if let characters = parsed.characters {
                    tokens.append(.characterClass(characters))
                } else {
                    tokens.append(.literal("["))
                }
                problems.append(contentsOf: parsed.problems)
                index = parsed.endIndex
            case "\\" where index + 1 < pattern.count:
                tokens.append(.literal(pattern[index + 1]))
                index += 2
            case let character:
                tokens.append(.literal(character))
                index += 1
            }
        }
        self.tokens = tokens
        self.problems = problems
    }

    func matches(_ component: some StringProtocol) -> Bool {
        let characters = Array(component)
        var tokenIndex = 0
        var characterIndex = 0
        var runToken = -1
        var runCharacter = 0
        while characterIndex < characters.count {
            if tokenIndex < tokens.count, tokens[tokenIndex].matches(characters[characterIndex]) {
                tokenIndex += 1
                characterIndex += 1
            } else if tokenIndex < tokens.count, tokens[tokenIndex].isAnyRun {
                runToken = tokenIndex
                runCharacter = characterIndex
                tokenIndex += 1
            } else if runToken >= 0 {
                tokenIndex = runToken + 1
                runCharacter += 1
                characterIndex = runCharacter
            } else {
                return false
            }
        }
        while tokenIndex < tokens.count, tokens[tokenIndex].isAnyRun { tokenIndex += 1 }
        return tokenIndex == tokens.count
    }
}

extension GitignoreSegment.Token {
    var isAnyRun: Bool {
        if case .anyRun = self { return true }
        return false
    }
}

extension Optional where Wrapped == GitignoreSegment.Token {
    var isAnyRun: Bool { self?.isAnyRun ?? false }
}
