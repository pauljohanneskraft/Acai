import Testing
import SwiftParser
import SwiftSyntax
@testable import AcaiSwift
@testable import AcaiCore

@Suite("Swift: Source Location Resolution")
struct SourceLocationResolverTests {

    private let source = """
    struct First {
        let name: String
        func alpha() {
            beta()
        }
        func beta() {}
    }

    struct Second {
        func gamma() {
            First().alpha()
        }
    }
    """

    @Test func everyNodeResolvesAgainstTheConverterTheResolverWasHanded() {
        let tree = Parser.parse(source: source)
        let resolver = SourceLocationResolver(
            fileName: "Two.swift", converter: SourceLocationConverter(fileName: "Two.swift", tree: tree))
        let structs = tree.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
        #expect(structs.count == 2)

        let locations = structs.map { resolver.sourceLocation(of: $0) }
        #expect(locations.map(\.filePath) == ["Two.swift", "Two.swift"])
        #expect(locations.map(\.line) == [1, 9])
        #expect(locations.map(\.column) == [1, 1])
        #expect(locations.map(\.endLine) == [7, 13])
    }

    @Test func aDetachedNodeDegradesToAnUnknownLocation() {
        let tree = Parser.parse(source: source)
        let resolver = SourceLocationResolver(
            fileName: "Two.swift", converter: SourceLocationConverter(fileName: "Two.swift", tree: tree))
        let detached = DeclReferenceExprSyntax(baseName: .identifier("orphan"))

        let location = resolver.sourceLocation(of: detached)
        #expect(location.filePath == "Two.swift")
        #expect(location.line == 0)
        #expect(location.column == 0)
        #expect(location.endLine == nil)
    }

    @Test func parsingAFileBuildsExactlyOneConverter() {
        var built = 0
        let artifact = SwiftCodeParser().parse(source: source, fileName: "Two.swift") { fileName, tree in
            built += 1
            return SourceLocationConverter(fileName: fileName, tree: tree)
        }

        #expect(built == 1)
        #expect(artifact.types.map(\.name) == ["First", "Second"])
        #expect(artifact.types.compactMap { $0.location?.line } == [1, 9])
        // Members resolve through the same converter rather than one of their own.
        #expect(artifact.types.first?.members.compactMap { $0.location?.line } == [2, 3, 6])
    }

    @Test func parsingAMalformedFileReusesThatOneConverterForItsDiagnostics() {
        var built = 0
        let artifact = SwiftCodeParser().parse(source: "struct Broken { func m( {", fileName: "Bad.swift") {
            fileName, tree in
            built += 1
            return SourceLocationConverter(fileName: fileName, tree: tree)
        }

        #expect(built == 1)
        #expect(artifact.metadata.hasParseErrors)
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.metadata.parseDiagnostics.allSatisfy { $0.location.line >= 1 })
    }
}
