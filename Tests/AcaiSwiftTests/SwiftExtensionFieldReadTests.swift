import Testing
@testable import AcaiSwift
@testable import AcaiCore

@Suite("Swift Extension Field Reads")
struct SwiftExtensionFieldReadTests {
    let parser = SwiftCodeParser()

    private let declaration = """
    class Counter {
        var total: Int = 0
        var label: String = ""
        var note: String? = nil
    }
    """

    private func enriched(_ sources: String...) -> CodeArtifact? {
        let fragments = sources.enumerated().map { index, source in
            parser.parse(source: source, fileName: "File\(index).swift")
        }
        return CodeArtifact(merging: fragments)?.enriched(configuration: parser.configuration)
    }

    private func reads(of name: String, in artifact: CodeArtifact?) -> [String] {
        let counter = artifact?.types.first { $0.name == "Counter" }
        return counter?.members.first { $0.name == name }?.fieldReads.map(\.name) ?? []
    }

    @Test func aSameFileExtensionReadsTheDeclarationsStoredProperty() {
        let artifact = enriched(declaration + """

        extension Counter {
            func describe() -> String { label + String(self.total) }
        }
        """)
        #expect(Set(reads(of: "describe", in: artifact)) == ["label", "total"])
    }

    @Test func aCrossFileExtensionReadsTheDeclarationsStoredProperty() {
        let artifact = enriched(declaration, """
        extension Counter {
            var isEmpty: Bool { total == 0 }
            func reset() { print(label.count) }
            func shout() { if let note { print(note) } }
        }
        """)
        #expect(reads(of: "isEmpty", in: artifact) == ["total"])
        #expect(reads(of: "reset", in: artifact) == ["label"])
        #expect(reads(of: "shout", in: artifact) == ["note"])
    }

    @Test func aLocalOrParameterNamedLikeAFieldIsNotARead() {
        let artifact = enriched(declaration, """
        extension Counter {
            func viaParameter(total: Int) -> Int { total }
            func viaLocal() -> Int { let total = 1; return total }
            func viaClosure(_ values: [Int]) -> [Int] { values.map { total in total } }
            func viaLoop(_ values: [Int]) -> Int { for total in values { return total }; return 0 }
            func viaShorthand(_ values: [Int]) -> [Int] { values.map { $0 } }
            func viaKeyPath(_ others: [Counter]) -> [Int] { others.map(\\.total) }
            func viaOther(_ other: Counter) -> Int { other.total }
        }
        """)
        for method in ["viaParameter", "viaLocal", "viaClosure", "viaLoop", "viaShorthand", "viaKeyPath", "viaOther"] {
            #expect(reads(of: method, in: artifact).isEmpty, "\(method)")
        }
    }

    @Test func anExplicitSelfReadCountsDespiteAShadowingLocal() {
        let artifact = enriched(declaration, """
        extension Counter {
            func compare(total: Int) -> Bool { self.total == total }
        }
        """)
        #expect(reads(of: "compare", in: artifact) == ["total"])
    }

    @Test func enrichmentResolvesDeferredReadsOnce() {
        let once = enriched(declaration, """
        extension Counter {
            func describe() -> String { label }
        }
        """)
        let twice = once?.enriched(configuration: parser.configuration)
        #expect(reads(of: "describe", in: twice) == ["label"])
        #expect(twice?.types.flatMap(\.members).allSatisfy { $0.deferredFieldReads == nil } == true)
    }

    @Test func anExtensionMethodJoinsTheCohesionClusterOfTheFieldItReads() {
        let artifact = enriched(declaration + """

        extension Counter {
            func increment() { print(total) }
            func describe() -> String { String(total) }
        }
        """)
        let counter = artifact?.types.first { $0.name == "Counter" }
        #expect(counter.map { LcomAnalysis(type: $0).componentCount } == 1)
    }
}
