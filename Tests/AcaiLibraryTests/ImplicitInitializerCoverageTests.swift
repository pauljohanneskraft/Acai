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

    /// Every construction form counts as resolved against a type with only an implicit constructor,
    /// while one of a type outside the project (`QString`) stays out of the total.
    @Test func cppKeepsFullCoverage() {
        let artifact = CppCodeParser().parse(source: """
        struct Helper { void run() {} };
        class Worker {
        public:
            void go() {
                Helper a;
                Helper b = Helper();
                Helper c{};
                Helper* d = new Helper();
                QString s;
            }
        };
        """, fileName: "Worker.cpp")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 4)
        #expect(graph.coverage.total == 4)
        #expect(graph.edges.isEmpty)
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

    @Test(arguments: [true, false])
    func jsKeepsFullCoverage(isTypeScript: Bool) {
        let artifact = JSCodeParser(isTypeScript: isTypeScript).parse(source: """
        class Helper { run() {} }
        class Worker {
            go() { const h = new Helper(); h.run(); }
        }
        """, fileName: isTypeScript ? "Worker.ts" : "Worker.js")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 2)
        #expect(graph.coverage.total == 2)
    }

    @Test(arguments: [true, false])
    func jsLeavesAConstructionOfAnOutsideTypeOutOfTheTotal(isTypeScript: Bool) {
        let artifact = JSCodeParser(isTypeScript: isTypeScript).parse(source: """
        class Helper { run() {} }
        class Worker {
            go() { const h = new Helper(); h.run(); throw new Error("no"); }
        }
        """, fileName: isTypeScript ? "Worker.ts" : "Worker.js")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 2)
        #expect(graph.coverage.total == 2)
    }

    @Test func javaLeavesAConstructionOfAnOutsideTypeOutOfTheTotal() {
        let artifact = JavaCodeParser().parse(source: """
        class Helper { void run() {} }
        class Worker {
            void go() { Helper h = new Helper(); h.run(); java.util.List<Helper> l = new ArrayList<>(); }
        }
        """, fileName: "Worker.java")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 2)
        #expect(graph.coverage.total == 2)
    }

    /// A construction of a type declared in another file is deferred, then promoted once the project merges.
    @Test func aCrossFileConstructionOfATypeWithOnlyAnImplicitInitializerIsResolved() {
        let helper = JSCodeParser().parse(source: "class Helper { run() {} }", fileName: "Helper.ts")
        let worker = JSCodeParser().parse(source: """
        class Worker {
            go() { const h = new Helper(); }
        }
        """, fileName: "Worker.ts")
        let artifact = helper.merging(with: worker).resolvingCallSiteReceivers()
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
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
