import Foundation
import Testing
@testable import AcaiApp

/// `FileFilter` (B62): a per-codebase ordered glob/regex allow/blocklist. Layer 0, per the
/// backlog's own "filter-excludes-file-from-parse" + `USABILITY_GUARDRAILS.md` §5's bounded-regex
/// requirement.
@Suite("FileFilter")
struct FileFilterTests {

    private func rule(
        _ pattern: String, _ syntax: FileFilter.Rule.Syntax, _ action: FileFilter.Rule.Action
    ) -> FileFilter.Rule {
        .init(pattern: pattern, syntax: syntax, action: action)
    }

    @Test("No rules includes everything, matching every codebase's behavior before this existed")
    func noRulesIncludesEverything() {
        let filter = FileFilter()
        #expect(filter.includes("Sources/Foo.swift"))
        #expect(filter.includes("Generated/Bar.swift"))
    }

    @Test("A single block rule excludes only its matches")
    func singleBlockRuleExcludesMatches() {
        let filter = FileFilter(rules: [rule("Generated/*", .glob, .block)])
        #expect(!filter.includes("Generated/Bar.swift"))
        #expect(filter.includes("Sources/Foo.swift"))
    }

    @Test("Block-everything then allow-a-subset scopes the codebase to just that subset")
    func blockThenAllowScopesToSubset() {
        let filter = FileFilter(rules: [
            rule("*", .glob, .block),
            rule("Sources/Core/*", .glob, .allow)
        ])
        #expect(filter.includes("Sources/Core/Foo.swift"))
        #expect(!filter.includes("Sources/Other/Bar.swift"))
    }

    @Test("Later rules override earlier ones, gitignore-style")
    func laterRulesOverrideEarlierOnes() {
        let filter = FileFilter(rules: [
            rule("*Tests.swift", .glob, .block),
            rule("ImportantTests.swift", .glob, .allow)
        ])
        #expect(!filter.includes("FooTests.swift"))
        #expect(filter.includes("ImportantTests.swift"))
    }

    @Test("A regex rule matches like NSRegularExpression")
    func regexRuleMatches() {
        let filter = FileFilter(rules: [rule("^Generated/.*\\.g\\.swift$", .regex, .block)])
        #expect(!filter.includes("Generated/Model.g.swift"))
        #expect(filter.includes("Generated/Model.swift"))
        #expect(filter.includes("Sources/Model.g.swift"))
    }

    @Test("A malformed regex rule doesn't match anything and doesn't crash")
    func malformedRegexDoesNotMatchOrCrash() {
        let filter = FileFilter(rules: [rule("(unclosed", .regex, .block)])
        #expect(filter.includes("anything.swift"))
    }

    @Test("A malformed regex rule surfaces a non-nil validation error; a glob rule never does")
    func malformedRegexSurfacesValidationError() {
        #expect(rule("(unclosed", .regex, .block).validationError != nil)
        #expect(rule("^valid$", .regex, .block).validationError == nil)
        #expect(rule("(unclosed", .glob, .block).validationError == nil)
    }

    @Test("A regex rule never evaluates against a pathologically long path")
    func regexRuleBoundsInputLength() {
        // Not a claim this specific pattern is catastrophic — just proof the length cap short-circuits
        // before `NSRegularExpression` ever sees an oversized input, per USABILITY_GUARDRAILS.md §5.
        let hugePath = String(repeating: "a/", count: 10_000) + "file.swift"
        let filter = FileFilter(rules: [rule("^(a/)+file\\.swift$", .regex, .block)])
        #expect(filter.includes(hugePath))
    }
}
