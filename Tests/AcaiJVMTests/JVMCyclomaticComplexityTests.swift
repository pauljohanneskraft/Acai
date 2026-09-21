import Testing
@testable import AcaiCore
@testable import AcaiJVM

/// Pins that a Java `switch`'s `default` label and a Kotlin `when`'s `else` branch each contribute
/// no decision point of their own — matching how `SwiftCyclomaticComplexity` treats `default` as
/// the "else", not a branch (issue #292).
@Suite("JVM: Cyclomatic Complexity")
struct JVMCyclomaticComplexityTests {
    @Test func javaSwitchWithDefaultExcludesDefaultLabel() {
        let source = """
        class S {
            String classify(int n) {
                switch (n) {
                    case 1: return "one";
                    case 2: return "two";
                    default: return "many";
                }
            }
        }
        """
        let artifact = JavaCodeParser().parse(source: source, fileName: "S.java")
        let method = artifact.types.first?.members.first { $0.name == "classify" }
        // 1 + case 1 + case 2 = 3 (default is the "else", not a branch)
        #expect(method?.cyclomaticComplexity == 3)
    }

    @Test func javaSwitchWithoutDefaultCountsOnlyCases() {
        let source = """
        class S {
            String classify(int n) {
                switch (n) {
                    case 1: return "one";
                    case 2: return "two";
                }
                return "unknown";
            }
        }
        """
        let artifact = JavaCodeParser().parse(source: source, fileName: "S.java")
        let method = artifact.types.first?.members.first { $0.name == "classify" }
        #expect(method?.cyclomaticComplexity == 3)
    }

    @Test func kotlinWhenWithElseExcludesElseBranch() {
        let source = """
        class S {
            fun classify(n: Int): String {
                return when (n) {
                    1 -> "one"
                    2 -> "two"
                    else -> "many"
                }
            }
        }
        """
        let artifact = KotlinCodeParser().parse(source: source, fileName: "S.kt")
        let method = artifact.types.first?.members.first { $0.name == "classify" }
        // 1 + entry 1 + entry 2 = 3 (else is the "default", not a branch)
        #expect(method?.cyclomaticComplexity == 3)
    }

    @Test func kotlinWhenWithoutElseCountsOnlyEntries() {
        let source = """
        class S {
            fun classify(n: Int): String {
                when (n) {
                    1 -> return "one"
                    2 -> return "two"
                }
                return "unknown"
            }
        }
        """
        let artifact = KotlinCodeParser().parse(source: source, fileName: "S.kt")
        let method = artifact.types.first?.members.first { $0.name == "classify" }
        #expect(method?.cyclomaticComplexity == 3)
    }
}
