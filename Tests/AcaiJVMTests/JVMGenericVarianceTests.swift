import Testing
@testable import AcaiCore
@testable import AcaiJVM

@Suite("JVM Generic Variance Tests")
struct JVMGenericVarianceTests {
    let kotlin = KotlinCodeParser()
    let java = JavaCodeParser()

    // MARK: - Kotlin declaration-site variance

    @Test func kotlinRecordsDeclarationSiteVariance() {
        let source = """
        interface Producer<out T> {
            fun produce(): T
        }

        interface Consumer<in T> {
            fun consume(item: T)
        }

        class Box<T>(val item: T)
        """
        let artifact = kotlin.parse(source: source, fileName: "Variance.kt")

        let producer = artifact.types.first { $0.name == "Producer" }
        #expect(producer?.genericParameters.first?.name == "T")
        #expect(producer?.genericParameters.first?.variance == .covariant)

        let consumer = artifact.types.first { $0.name == "Consumer" }
        #expect(consumer?.genericParameters.first?.name == "T")
        #expect(consumer?.genericParameters.first?.variance == .contravariant)

        // An unannotated parameter is left `nil`, not defaulted to `.invariant` — Kotlin's default
        // is invariance, but nothing was declared, and the two are worth telling apart.
        let box = artifact.types.first { $0.name == "Box" }
        #expect(box?.genericParameters.first?.variance == nil)
    }

    @Test func kotlinVarianceSurvivesAConstraint() {
        let source = """
        interface Sink<in T : Comparable<T>> {
            fun accept(value: T)
        }
        """
        let artifact = kotlin.parse(source: source, fileName: "Sink.kt")
        let parameter = artifact.types.first { $0.name == "Sink" }?.genericParameters.first
        #expect(parameter?.name == "T")
        #expect(parameter?.variance == .contravariant)
        #expect(parameter?.constraints.first?.type.name == "Comparable")
    }

    @Test func kotlinSpellsVarianceWithItsOwnKeywords() {
        let keywords = kotlin.configuration.varianceKeywords
        #expect(GenericParameter(name: "T", variance: .covariant)
            .umlDisplayString(varianceKeywords: keywords) == "out T")
        #expect(GenericParameter(name: "T", variance: .contravariant)
            .umlDisplayString(varianceKeywords: keywords) == "in T")
        #expect(GenericParameter(name: "T").umlDisplayString(varianceKeywords: keywords) == "T")
    }

    // MARK: - Java use-site variance

    /// Java marks variance at the *use* site, so a type parameter never carries it — the wildcard
    /// does, and reaches the diagram through the type reference's own spelling.
    @Test func javaTypeParametersCarryNoVariance() {
        let source = """
        public class Box<T extends Number> {
            private T value;
        }
        """
        let artifact = java.parse(source: source, fileName: "Box.java")
        let parameter = artifact.types.first { $0.name == "Box" }?.genericParameters.first
        #expect(parameter?.name == "T")
        #expect(parameter?.variance == nil)
        #expect(java.configuration.varianceKeywords.isEmpty)
    }

    @Test func javaWildcardsKeepTheirOwnSpelling() {
        let source = """
        public class Wildcards {
            private List<? extends Number> covariant;
            private List<? super Integer> contravariant;
        }
        """
        let artifact = java.parse(source: source, fileName: "Wildcards.java")
        let type = artifact.types.first { $0.name == "Wildcards" }

        let covariant = type?.members.first { $0.name == "covariant" }?.type
        #expect(covariant?.genericArguments.first?.name == "? extends Number")

        let contravariant = type?.members.first { $0.name == "contravariant" }?.type
        #expect(contravariant?.genericArguments.first?.name == "? super Integer")
    }
}
