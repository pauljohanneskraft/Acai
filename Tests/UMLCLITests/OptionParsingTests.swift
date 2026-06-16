import ArgumentParser
import Testing
@testable import UMLCLI

/// Verifies the `ExpressibleByArgument` option enums under `Sources/UMLCLI/Options/`: valid raw
/// values construct, map to the right domain value, and invalid raw values fail to parse.
@Suite("Option Parsing")
struct OptionParsingTests {

    @Test func languageOptionParsesAndMaps() throws {
        #expect(LanguageOption(argument: "swift")?.sourceLanguage == .swift)
        #expect(LanguageOption(argument: "typescript")?.sourceLanguage == .typeScript)
        #expect(LanguageOption(argument: "javascript")?.sourceLanguage == .javaScript)
        #expect(LanguageOption(argument: "dart")?.sourceLanguage == .dart)
        #expect(LanguageOption(argument: "cobol") == nil)
    }

    @Test func formatOptionParsesAndMaps() {
        #expect(FormatOption(argument: "dot")?.diagramFormat == .dot)
        #expect(FormatOption(argument: "mermaid")?.diagramFormat == .mermaid)
        #expect(FormatOption(argument: "svg") == nil)
    }

    @Test func directionOptionParsesAndMaps() {
        #expect(DirectionOption(argument: "TB")?.layoutDirection == .topToBottom)
        #expect(DirectionOption(argument: "LR")?.layoutDirection == .leftToRight)
        #expect(DirectionOption(argument: "BT")?.layoutDirection == .bottomToTop)
        #expect(DirectionOption(argument: "RL")?.layoutDirection == .rightToLeft)
        #expect(DirectionOption(argument: "diagonal") == nil)
    }

    @Test func themeOptionParsesAllCases() {
        #expect(ThemeOption(argument: "default") != nil)
        #expect(ThemeOption(argument: "dark") != nil)
        #expect(ThemeOption(argument: "solarized") == nil)
    }

    @Test func groupByOptionParsesAndMaps() {
        #expect(GroupByOption(argument: "file")?.groupingStrategy == .byFile)
        #expect(GroupByOption(argument: "namespace")?.groupingStrategy == .byNamespace)
        // The `none` strategy clashes with `Optional.none` under leading-dot syntax, so check it by
        // ruling out the other cases instead of an `== .none` comparison.
        let noneStrategy = GroupByOption(argument: "none")?.groupingStrategy
        #expect(noneStrategy != nil)
        #expect(noneStrategy != .byFile)
        #expect(noneStrategy != .byNamespace)
        #expect(GroupByOption(argument: "module") == nil)
    }

    @Test func relationshipKindOptionParsesAndMaps() {
        #expect(RelationshipKindOption(argument: "inheritance")?.kind == .inheritance)
        #expect(RelationshipKindOption(argument: "extension")?.kind == .extension)
        #expect(RelationshipKindOption(argument: "nesting")?.kind == .nesting)
        #expect(RelationshipKindOption(argument: "uses") == nil)
    }

    @Test func focusDirectionOptionParsesAndMaps() {
        #expect(FocusDirectionOption(argument: "dependencies")?.direction == .dependencies)
        #expect(FocusDirectionOption(argument: "dependents")?.direction == .dependents)
        #expect(FocusDirectionOption(argument: "both")?.direction == .both)
        #expect(FocusDirectionOption(argument: "sideways") == nil)
    }

    @Test func allEnumsRejectEmptyString() {
        #expect(LanguageOption(argument: "") == nil)
        #expect(FormatOption(argument: "") == nil)
        #expect(DirectionOption(argument: "") == nil)
        #expect(ThemeOption(argument: "") == nil)
        #expect(GroupByOption(argument: "") == nil)
        #expect(RelationshipKindOption(argument: "") == nil)
        #expect(FocusDirectionOption(argument: "") == nil)
    }
}
