import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

@Suite("Constructions of types with only an implicit initializer")
struct ImplicitInitializerCoverageTests {
    @Test func swiftKeepsFullCoverage() {
        let artifact = SwiftCodeParser().parse(source: """
        struct Helper { func run() {} }
        struct Worker {
            func go() { Helper().run() }
            func make() -> Helper { Helper.init() }
        }
        """, fileName: "Worker.swift")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == graph.coverage.total)
        #expect(graph.coverage.total == 3)
    }

    @Test func javaKeepsFullCoverage() {
        let artifact = JavaCodeParser().parse(source: """
        class Helper { void run() {} }
        class Worker {
            void go() { Helper h = new Helper(); h.run(); }
        }
        """, fileName: "Worker.java")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 2)
        #expect(graph.coverage.total == 2)
    }

    @Test func kotlinKeepsFullCoverage() {
        let artifact = KotlinCodeParser().parse(source: """
        class Helper { fun run() {} }
        class Worker {
            fun go() { val h = Helper(); h.run() }
        }
        """, fileName: "Worker.kt")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 2)
        #expect(graph.coverage.total == 2)
    }
}
