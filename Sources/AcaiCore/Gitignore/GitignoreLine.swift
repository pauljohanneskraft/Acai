/// One raw line of a `.gitignore`, compiled on demand into the rule it expresses.
///
/// Every line compiles to something: a blank or a comment is nothing, a line git would read is a
/// pattern, and a line neither of those is refused with a reason rather than guessed at.
struct GitignoreLine: Sendable {

    enum Outcome: Sendable {
        /// Blank, or a comment — git reads no rule from it and neither do we.
        case none
        /// A usable rule. `problem` describes something git tolerates but is worth telling the user
        /// about, such as a `[` that is never closed and so matches literally.
        case rule(GitignorePattern, problem: String?)
        /// No rule could be read; the line is skipped and the reason reported.
        case refused(String)
    }

    /// A line longer than this is refused. `.gitignore` lines are path patterns, not documents, and
    /// this file is external input to the analyzer.
    static let maximumLength = 4096

    let text: String

    var outcome: Outcome {
        guard text.count <= Self.maximumLength else {
            return .refused("pattern is longer than \(Self.maximumLength) characters")
        }
        var characters = trimmingUnescapedTrailingWhitespace(Array(text))
        guard let first = characters.first, first != "#" else { return .none }

        let isNegated = first == "!"
        // `\#` and `\!` are how git spells a pattern that starts with a character it would
        // otherwise read as a comment marker or a negation.
        let isEscapedMarker = first == "\\" && (characters.dropFirst().first.map { $0 == "#" || $0 == "!" } ?? false)
        if isNegated || isEscapedMarker { characters.removeFirst() }
        guard !characters.isEmpty else { return .refused("pattern is empty") }

        let matchesDirectoriesOnly = characters.last == "/"
        if matchesDirectoriesOnly { characters.removeLast() }
        let isRooted = characters.first == "/"
        if isRooted { characters.removeFirst() }
        guard !characters.isEmpty else { return .refused("pattern is empty") }

        return compiled(
            characters, isNegated: isNegated, matchesDirectoriesOnly: matchesDirectoriesOnly,
            isAnchored: isRooted || characters.contains("/")
        )
    }

    private func compiled(
        _ characters: [Character], isNegated: Bool, matchesDirectoriesOnly: Bool, isAnchored: Bool
    ) -> Outcome {
        var segments: [GitignorePattern.Segment] = []
        var problems: [String] = []
        for part in characters.split(separator: "/", omittingEmptySubsequences: false) {
            if part.elementsEqual(["*", "*"]) {
                segments.append(.anyComponents)
                continue
            }
            guard !part.isEmpty else {
                return .refused("pattern has an empty path component")
            }
            let segment = GitignoreSegment(pattern: Array(part))
            problems.append(contentsOf: segment.problems)
            segments.append(.component(segment))
        }
        let pattern = GitignorePattern(
            isNegated: isNegated, matchesDirectoriesOnly: matchesDirectoriesOnly,
            isAnchored: isAnchored, segments: segments
        )
        return .rule(pattern, problem: problems.first)
    }

    /// git strips trailing spaces from a pattern unless the last one is escaped, so `foo\ ` names a
    /// file ending in a space and `foo   ` names `foo`.
    private func trimmingUnescapedTrailingWhitespace(_ characters: [Character]) -> [Character] {
        var characters = characters
        while let last = characters.last, last == " " || last == "\t" {
            var backslashes = 0
            var index = characters.count - 2
            while index >= 0, characters[index] == "\\" {
                backslashes += 1
                index -= 1
            }
            guard backslashes.isMultiple(of: 2) else { break }
            characters.removeLast()
        }
        return characters
    }
}
