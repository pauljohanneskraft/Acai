import Testing
@testable import AcaiCore

/// The `.gitignore` grammar subset the walker reads, line by line. These pin the shapes git
/// documents — and the shapes it does not, which must be refused with a reason rather than guessed
/// at, because a misread rule silently removes source from the analysis.
@Suite("Gitignore pattern grammar")
struct GitignorePatternTests {

    private func pattern(_ line: String) throws -> GitignorePattern {
        guard case .rule(let pattern, _) = GitignoreLine(text: line).outcome else {
            throw MatchFailure(line: line)
        }
        return pattern
    }

    private func problem(_ line: String) -> String? {
        switch GitignoreLine(text: line).outcome {
        case .rule(_, let problem):
            problem
        case .refused(let reason):
            reason
        case .noRule:
            nil
        }
    }

    private func matches(_ line: String, _ path: String, isDirectory: Bool = false) throws -> Bool {
        let components = path.split(separator: "/")
        return try pattern(line).matches(components[...], isDirectory: isDirectory)
    }

    private struct MatchFailure: Error {
        let line: String
    }

    @Test("blank lines and comments carry no rule")
    func blanksAndComments() {
        for line in ["", "   ", "# a comment", "#"] {
            #expect(GitignoreLine(text: line).outcome.isNone, "\(line) should carry no rule")
        }
    }

    @Test("a backslash escapes a leading comment or negation marker")
    func escapedMarkers() throws {
        #expect(try matches("\\#notes", "#notes"))
        #expect(try matches("\\!bang", "!bang"))
        #expect(try pattern("\\!bang").isNegated == false)
    }

    @Test("a leading bang negates")
    func negation() throws {
        #expect(try pattern("!keep.fx").isNegated)
        #expect(try matches("!keep.fx", "keep.fx"))
    }

    @Test("trailing whitespace is dropped unless the last space is escaped")
    func trailingWhitespace() throws {
        #expect(try matches("notes.txt   ", "notes.txt"))
        #expect(try matches("notes\\ ", "notes "))
    }

    @Test("a trailing slash restricts the rule to directories")
    func directoryOnly() throws {
        #expect(try matches("build/", "build", isDirectory: true))
        #expect(try matches("build/", "build", isDirectory: false) == false)
    }

    @Test("a leading slash anchors to the file's own directory")
    func leadingSlashAnchors() throws {
        #expect(try matches("/top.fx", "top.fx"))
        #expect(try matches("/top.fx", "nested/top.fx") == false)
    }

    @Test("an interior slash anchors; no slash matches at any depth")
    func interiorSlashAnchors() throws {
        #expect(try matches("doc/frotz", "doc/frotz"))
        #expect(try matches("doc/frotz", "a/doc/frotz") == false)
        // Unanchored rules are matched against one component at a time by the filter, which is how
        // `*.log` reaches every depth.
        #expect(try matches("*.log", "debug.log"))
    }

    @Test("double star spans whole components, in any position")
    func doubleStar() throws {
        #expect(try matches("**/generated", "a/b/generated"))
        #expect(try matches("**/generated", "generated"))
        #expect(try matches("src/**/fixtures", "src/fixtures"))
        #expect(try matches("src/**/fixtures", "src/a/b/fixtures"))
        #expect(try matches("src/**", "src/a/b.fx"))
        #expect(try matches("src/**", "other/a.fx") == false)
    }

    @Test("star and question mark stay inside one component")
    func singleComponentWildcards() throws {
        #expect(try matches("a*c.fx", "abbbc.fx"))
        #expect(try matches("a?c.fx", "abc.fx"))
        #expect(try matches("a?c.fx", "abbc.fx") == false)
        // An unanchored rule is matched one component at a time, so a separator only comes into
        // play once the rule is anchored.
        #expect(try matches("src/*.fx", "src/b.fx"))
        #expect(try matches("src/*.fx", "src/a/b.fx") == false, "a `*` must not cross a separator")
    }

    @Test("character classes match sets, ranges and negations")
    func characterClasses() throws {
        #expect(try matches("[abc].fx", "b.fx"))
        #expect(try matches("[abc].fx", "d.fx") == false)
        #expect(try matches("[a-f]*.fx", "cat.fx"))
        #expect(try matches("[!a-f]*.fx", "cat.fx") == false)
        #expect(try matches("[^a-f]*.fx", "zebra.fx"))
    }

    @Test("a wildcard-dense pattern terminates rather than backtracking exponentially")
    func boundedMatching() throws {
        let line = String(repeating: "*a", count: 24)
        let path = String(repeating: "a", count: 64) + "!"
        #expect(try matches(line, path) == false)
    }

    @Test("an unclosed bracket is reported and matched literally, as git does")
    func unclosedBracket() throws {
        #expect(problem("a[bc.fx")?.contains("never closed") == true)
        #expect(try matches("a[bc.fx", "a[bc.fx"))
    }

    @Test("a backwards range is reported rather than silently matching nothing")
    func backwardsRange() {
        #expect(problem("[z-a].fx")?.contains("runs backwards") == true)
    }

    @Test("an over-long line is refused rather than compiled")
    func overLongLine() {
        let line = String(repeating: "a", count: GitignoreLine.maximumLength + 1)
        #expect(problem(line)?.contains("longer than") == true)
    }

    @Test("a pattern with an empty component is refused")
    func emptyComponent() {
        #expect(problem("a//b")?.contains("empty path component") == true)
    }
}

extension GitignoreLine.Outcome {
    fileprivate var isNone: Bool {
        if case .noRule = self { return true }
        return false
    }
}
