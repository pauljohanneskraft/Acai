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

    @Test func pythonKeepsFullCoverage() {
        let artifact = PythonCodeParser().parse(source: """
        class Helper:
            def run(self): pass

        class Worker:
            def go(self):
                Helper()
        """, fileName: "worker.py")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.edges.isEmpty)
    }

    private func pythonProjectGraph(declaring classes: String) -> CallGraph {
        let declared = PythonCodeParser().parse(source: classes, fileName: "models.py")
        let worker = PythonCodeParser().parse(source: """
        class Worker:
            def go(self):
                Helper()
                Path("a")
                Decimal("1")
        """, fileName: "worker.py")
        return CallGraphBuilder().build(from: declared.merging(with: worker).resolvingCallSiteReceivers())
    }

    @Test func pythonConstructsAClassFromAnotherFileThroughItsInitializer() {
        let graph = pythonProjectGraph(declaring: """
        class Helper:
            def __init__(self): pass
        """)
        #expect(graph.edges.contains { $0.from == "Worker.go" && $0.to == "Helper.__init__" })
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
    }

    /// `Path` and `Decimal` are library classes, so they stay out of the total.
    @Test func pythonCountsAClassFromAnotherFileWithNoInitializerAsResolved() {
        let graph = pythonProjectGraph(declaring: """
        class Helper:
            def run(self): pass
        """)
        #expect(graph.edges.isEmpty)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
    }

    /// A capitalised function declared in the same file is called, not constructed.
    @Test func pythonCallsACapitalisedFunctionDeclaredInTheFile() {
        let artifact = PythonCodeParser().parse(source: """
        def Helper(): pass

        class Worker:
            def go(self):
                Helper()
        """, fileName: "worker.py")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.edges.contains { $0.from == "Worker.go" && $0.to == "Helper" })
    }

    /// A capitalised factory function from another file reads as a speculative construction, so it
    /// draws no edge and stays out of the total.
    @Test func pythonLeavesACapitalisedFunctionFromAnotherFileOutOfTheTotal() {
        let graph = pythonProjectGraph(declaring: "def Helper(): pass")
        #expect(graph.edges.isEmpty)
        #expect(graph.coverage.total == 0)
    }

    /// A subclass declaring no `__init__` of its own counts as resolved, but draws no edge to the
    /// inherited one: the builder walks no supertype chain, for constructors as for methods.
    @Test func pythonCountsAnInheritedInitializerAsResolvedWithoutAnEdge() {
        let artifact = PythonCodeParser().parse(source: """
        class Base:
            def __init__(self): pass

        class Child(Base):
            pass

        class Worker:
            def go(self):
                Child()
        """, fileName: "worker.py")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.edges.isEmpty)
    }
}
