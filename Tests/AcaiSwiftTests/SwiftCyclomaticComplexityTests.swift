import Testing
@testable import AcaiCore
@testable import AcaiSwift

/// Covers per-method cyclomatic complexity (`Member.cyclomaticComplexity`): `1 +` each structural
/// decision point, counted at *every* nesting depth (McCabe complexity is a flat count of decision
/// points — nesting does not collapse, but nor does it compound extra beyond one-per-branch).
@Suite("Swift: Cyclomatic Complexity")
struct SwiftCyclomaticComplexityTests {
    let parser = SwiftCodeParser()

    private func method(_ name: String, in source: String) -> Member? {
        parser.parse(source: source, fileName: "Test.swift")
            .types.first?.members.first { $0.name == name }
    }

    @Test func straightLineMethodHasBaseComplexity() {
        let source = """
        struct S {
            func plain() -> Int { return 1 }
        }
        """
        #expect(method("plain", in: source)?.cyclomaticComplexity == 1)
    }

    @Test func nestedDecisionsEachAddOne() {
        // if → nested if → nested while: three decision points at increasing depth. Each adds 1, so
        // complexity is 4 — the walk descends into nested bodies rather than counting only the top if.
        let source = """
        struct S {
            func nested(_ xs: [Int]) {
                if !xs.isEmpty {
                    if xs[0] > 0 {
                        while true { break }
                    }
                }
            }
        }
        """
        #expect(method("nested", in: source)?.cyclomaticComplexity == 4)
    }

    @Test func switchCasesAndGuardCount() {
        let source = """
        struct S {
            func classify(_ n: Int) -> String {
                guard n != 0 else { return "zero" }   // +1
                switch n {                             // cases below
                case 1: return "one"                   // +1
                case 2: return "two"                   // +1
                default: return "many"                 // default: no +1
                }
            }
        }
        """
        // 1 + guard + case 1 + case 2 = 4 (default is the "else", not a branch)
        #expect(method("classify", in: source)?.cyclomaticComplexity == 4)
    }
}
