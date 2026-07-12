import ArgumentParser
import Testing
@testable import UMLCLI

/// The `--include-generated` flag shared by the analysis commands: absent means generated types are
/// excluded (the default), present means they're included.
@Suite("Generated scope option")
struct GeneratedScopeOptionTests {

    @Test func defaultsToExcluded() throws {
        #expect(try GeneratedScopeOption.parse([]).includeGenerated == false)
    }

    @Test func flagIncludesGenerated() throws {
        #expect(try GeneratedScopeOption.parse(["--include-generated"]).includeGenerated == true)
    }
}
