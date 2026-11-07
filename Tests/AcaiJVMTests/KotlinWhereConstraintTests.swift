import Testing
@testable import AcaiCore
@testable import AcaiJVM

@Suite("Kotlin where-constraint Tests")
struct KotlinWhereConstraintTests {
    let kotlin = KotlinCodeParser()

    @Test func functionKeepsEveryWhereBound() {
        let source = """
        interface A
        interface B
        fun <T> f(value: T): Int where T : A, T : B = 0
        """
        let artifact = kotlin.parse(source: source, fileName: "F.kt")
        let params = artifact.freestandingFunctions.first { $0.name == "f" }?.genericParameters ?? []
        #expect(params.map(\.name) == ["T"])
        #expect(params.first?.constraints.map(\.type.name) == ["A", "B"])
        #expect(params.first?.constraints.allSatisfy { $0.kind == .conformance } == true)
    }

    @Test func inlineBoundIsMergedWithWhereBound() {
        let source = """
        interface A
        interface B
        fun <T : A, U> f(first: T, second: U): Int where T : B, U : A = 0
        """
        let artifact = kotlin.parse(source: source, fileName: "F.kt")
        let params = artifact.freestandingFunctions.first { $0.name == "f" }?.genericParameters ?? []
        #expect(params.map(\.name) == ["T", "U"])
        #expect(params.first?.constraints.map(\.type.name) == ["A", "B"])
        #expect(params.last?.constraints.map(\.type.name) == ["A"])
    }

    @Test func typeDeclarationsMergeWhereBounds() {
        let source = """
        interface A
        interface B
        class Shelf<T>(val item: T) where T : A, T : B
        interface Rack<T> where T : A, T : B
        class Holder {
            fun <T> put(item: T): Int where T : A, T : B = 0
        }
        """
        let artifact = kotlin.parse(source: source, fileName: "T.kt")
        for typeName in ["Shelf", "Rack"] {
            let params = artifact.types.first { $0.name == typeName }?.genericParameters ?? []
            #expect(params.map(\.name) == ["T"], "\(typeName)")
            #expect(params.first?.constraints.map(\.type.name) == ["A", "B"], "\(typeName)")
        }
        let method = artifact.types.first { $0.name == "Holder" }?.members.first { $0.name == "put" }
        #expect(method?.genericParameters.first?.constraints.map(\.type.name) == ["A", "B"])
    }

    @Test func nullableWhereBoundIsKept() {
        let source = """
        interface A
        fun <T> f(value: T): Int where T : A? = 0
        """
        let artifact = kotlin.parse(source: source, fileName: "F.kt")
        let bound = artifact.freestandingFunctions.first?.genericParameters.first?.constraints.first
        #expect(bound?.type.name == "A")
        #expect(bound?.type.isOptional == true)
    }
}
