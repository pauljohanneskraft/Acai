import Testing
@testable import AcaiCore
@testable import AcaiSwift

/// Covers construction/body type-reference capture (`Member.referencedTypeNames`) used by the coupling
/// metrics: constructions and static access in method bodies and in property initializers — while
/// deliberately skipping computed-property accessor bodies (walking deeply nested `var body` views
/// would overflow the stack).
@Suite("Swift: Body Type References")
struct SwiftBodyReferenceTests {
    let parser = SwiftCodeParser()

    private func member(_ name: String, of typeName: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        return artifact.types.first { $0.name == typeName }?.members.first { $0.name == name }
    }

    @Test func capturesConstructionAndStaticAccessInMethodBody() {
        let source = """
        struct Widget {}
        enum Palette { static let main = 0 }
        struct Factory {
            func build() {
                let w = Widget()
                _ = Palette.main
            }
        }
        """
        let build = member("build", of: "Factory", in: source)
        #expect(build?.referencedTypeNames.contains("Widget") == true)
        #expect(build?.referencedTypeNames.contains("Palette") == true)
    }

    @Test func capturesConstructionInPropertyInitializer() {
        let source = """
        struct Parser {}
        struct Registry {
            static let parsers = [Parser()]
        }
        """
        let parsers = member("parsers", of: "Registry", in: source)
        #expect(parsers?.referencedTypeNames.contains("Parser") == true)
    }

    @Test func ignoresComputedPropertyAccessorBodies() {
        let source = """
        struct Widget {}
        struct Box {
            var count: Int { let w = Widget(); return 0 }
        }
        """
        let count = member("count", of: "Box", in: source)
        #expect(count?.referencedTypeNames.contains("Widget") != true)
    }
}
