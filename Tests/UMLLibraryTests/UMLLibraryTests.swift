import Testing
import UMLDiagram
import UMLKotlin
import UMLLibrary
import UMLSwift

@Suite("UML Library Tests")
struct UMLLibraryTests {
    @Test func testKotlin() async throws {
        let source = """
        sealed class SuperClass {
            object SubClass1 : SuperClass()
            data class SubClass2(val property1: String): SuperClass()
        }
        """
        let artifact = KotlinCodeParser().parse(source: source, fileName: "Source.kt")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
    }

    @Test func testSwift() async throws {
        let source = """
        enum SuperClass {
            case subClass1(SubClass1)
            case subClass2(SubClass2)
            struct SubClass1 {}
            struct SubClass2 {
                let property1: String
            }
        }
        """
        let artifact = SwiftCodeParser().parse(source: source, fileName: "Source.swift")
        print(artifact)
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
    }
}
