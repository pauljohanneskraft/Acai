import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// `FreeformDiagram.Node.Member`/`Parameter`: structured property/method fields, and back-compat
/// decoding of members saved before structured parameter editing existed.
@Suite("FreeformDiagram Member")
struct FreeformDiagramMemberTests {

    @Test("A member saved before structured parameters existed still decodes")
    func decodesLegacyJSONWithoutStructuredParametersKey() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","name":"doWork","type":"String","accessLevel":"internal",
         "isStatic":false,"isAbstract":false,"parameters":"input: Int"}
        """.utf8)

        let decoded = try JSONDecoder().decode(FreeformDiagram.Node.Member.self, from: json)

        #expect(decoded.name == "doWork")
        #expect(decoded.parameters == "input: Int")
        #expect(decoded.structuredParameters.isEmpty)
        // With no structured parameters, `displayString` falls back to the legacy free-text list.
        #expect(decoded.displayString == "doWork(input: Int): String")
    }

    @Test("Structured parameters round-trip through Codable and take priority over legacy text")
    func structuredParametersRoundTripAndTakePriority() throws {
        var member = FreeformDiagram.Node.Member(name: "doWork", type: "String", parameters: "stale: Int")
        member.structuredParameters = [.init(name: "input", type: "Int"), .init(name: "flag", type: "Bool")]

        let data = try JSONEncoder().encode(member)
        let decoded = try JSONDecoder().decode(FreeformDiagram.Node.Member.self, from: data)

        #expect(decoded.structuredParameters == member.structuredParameters)
        // Structured parameters win over the stale legacy `parameters` string once present.
        #expect(decoded.displayString == "doWork(input: Int, flag: Bool): String")
    }

    @Test("displayString omits parens for a property with no parameters")
    func displayStringOmitsParensForProperty() {
        let property = FreeformDiagram.Node.Member(name: "count", type: "Int")
        #expect(property.displayString == "count: Int")
    }
}
