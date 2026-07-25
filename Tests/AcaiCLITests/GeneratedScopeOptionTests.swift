import ArgumentParser
import Testing
@testable import AcaiCLI

@Suite("Generated scope option")
struct GeneratedScopeOptionTests {

    @Test func defaultsToExcluded() throws {
        #expect(try GeneratedScopeOption.parse([]).includeGenerated == false)
    }

    @Test func flagIncludesGenerated() throws {
        #expect(try GeneratedScopeOption.parse(["--include-generated"]).includeGenerated == true)
    }
}
