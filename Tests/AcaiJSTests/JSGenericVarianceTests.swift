import Testing
@testable import AcaiCore
@testable import AcaiJS

@Suite("TypeScript Generic Variance")
struct JSGenericVarianceTests {
    let parser = JSCodeParser(isTypeScript: true)

    @Test func recordsVarianceAnnotations() {
        let source = """
        interface Producer<out T> {
            produce(): T;
        }

        interface Consumer<in T> {
            consume(item: T): void;
        }

        interface Box<T> {
            item: T;
        }
        """
        let artifact = parser.parse(source: source, fileName: "variance.ts")

        let producer = artifact.types.first { $0.name == "Producer" }
        #expect(producer?.genericParameters.first?.name == "T")
        #expect(producer?.genericParameters.first?.variance == .covariant)

        let consumer = artifact.types.first { $0.name == "Consumer" }
        #expect(consumer?.genericParameters.first?.name == "T")
        #expect(consumer?.genericParameters.first?.variance == .contravariant)

        let box = artifact.types.first { $0.name == "Box" }
        #expect(box?.genericParameters.first?.variance == nil)
    }

    /// `in out T` is TypeScript's way of writing an explicitly invariant parameter.
    @Test func bothModifiersTogetherAreInvariant() {
        let source = """
        interface Cell<in out T> {
            value: T;
        }
        """
        let artifact = parser.parse(source: source, fileName: "cell.ts")
        let parameter = artifact.types.first { $0.name == "Cell" }?.genericParameters.first
        #expect(parameter?.name == "T")
        #expect(parameter?.variance == .invariant)
    }

    @Test func varianceSurvivesAConstraint() {
        let source = """
        interface Sink<in T extends Error> {
            accept(value: T): void;
        }
        """
        let artifact = parser.parse(source: source, fileName: "sink.ts")
        let parameter = artifact.types.first { $0.name == "Sink" }?.genericParameters.first
        #expect(parameter?.name == "T")
        #expect(parameter?.variance == .contravariant)
        #expect(parameter?.constraints.first?.type.name == "Error")
    }
}
