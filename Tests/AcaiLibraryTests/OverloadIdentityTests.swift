import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// Issue #506: a call-graph node keyed by type and member name alone merged an overload set into
/// one node, so an overload calling a sibling read as recursion and a call to any overload marked
/// the rest live. These drive the real parsers, since what makes the fix work is each one recording
/// the call's argument list.
@Suite("Overload node identity")
struct OverloadIdentityTests {

    // MARK: - Delegating initializers

    @Test func aDelegatingSwiftInitializerIsNotACycle() {
        let artifact = SwiftCodeParser().parse(source: """
        class Widget {
            init(name: String) { self.init(name: name, size: 0) }
            init(name: String, size: Int) {}
        }
        """, fileName: "Widget.swift")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.edges == [
            CallGraph.Edge(from: "Widget.init(name:String)", to: "Widget.init(name:String,size:Int)", weight: 1)
        ])
        #expect(MethodCycles(artifact: artifact).clusters.isEmpty)
    }

    @Test func aDelegatingJavaConstructorIsNotACycle() {
        let artifact = JavaCodeParser().parse(source: """
        class Widget {
            Widget(String name) { this(name, 0); }
            Widget(String name, int size) {}
        }
        """, fileName: "Widget.java")
        #expect(MethodCycles(artifact: artifact).clusters.isEmpty)
    }

    // MARK: - Overloads as separate nodes

    /// Each overload a call reaches is its own node, and the arity the call passes says which. The
    /// graph only ever holds callers and resolved callees, so the overload nobody called is absent
    /// here — it surfaces in the dead-code scan below instead.
    @Test func overloadsAreSeparateNodesAndTheCallPicksByArity() {
        let artifact = SwiftCodeParser().parse(source: """
        class Widget {
            public func use() { render("a"); render("b", times: 2) }
            private func render(_ text: String) {}
            private func render(_ text: String, times: Int) {}
        }
        """, fileName: "Widget.swift")
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.nodes.map(\.id).sorted()
            == ["Widget.render(String)", "Widget.render(String,times:Int)", "Widget.use()"])
        #expect(graph.edges == [
            CallGraph.Edge(from: "Widget.use()", to: "Widget.render(String)", weight: 1),
            CallGraph.Edge(from: "Widget.use()", to: "Widget.render(String,times:Int)", weight: 1)
        ])
    }

    /// The whole point of keying by signature: the sibling the call did not reach is still reported.
    @Test func anUncalledOverloadIsDeadWhileItsCalledSiblingIsNot() {
        let artifact = SwiftCodeParser().parse(source: """
        class Widget {
            public func use() { render("a") }
            private func render(_ text: String) {}
            private func render(_ text: String, times: Int) {}
        }
        """, fileName: "Widget.swift")
        let report = DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id) == ["Widget.render(String,times:Int)"])
    }

    /// Labels, not only arity: both overloads take one argument, so only the label it spells says
    /// which was reached.
    @Test func aLabelledCallPicksTheOverloadCarryingThatLabel() {
        let artifact = SwiftCodeParser().parse(source: """
        class Widget {
            public func use() { render(text: "a") }
            private func render(text: String) {}
            private func render(image: String) {}
        }
        """, fileName: "Widget.swift")
        let report = DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver).report
        #expect(report.candidates.map(\.id) == ["Widget.render(image:String)"])
    }

    // MARK: - File-scoped free functions

    @Test func sameNamedStaticCFunctionsInDifferentFilesAreDistinctNodes() {
        let left = CCodeParser().parse(source: """
        static int helper(int n) { return n; }
        int a_entry(int n) { return helper(n); }
        """, fileName: "a.c")
        let right = CCodeParser().parse(source: """
        static int helper(int n) { return n + 1; }
        int b_entry(int n) { return helper(n); }
        """, fileName: "b.c")
        let graph = CallGraphBuilder().build(from: left.merging(with: right).resolvingCallSiteReceivers())

        #expect(graph.nodes.filter { $0.methodName == "helper" }.map(\.id).sorted()
            == ["a.c:helper(int)", "b.c:helper(int)"])
        // Each entry point reaches the helper in its own file, not the other's.
        #expect(graph.edges.contains(
            CallGraph.Edge(from: "a.c:a_entry(int)", to: "a.c:helper(int)", weight: 1)))
        #expect(graph.edges.contains(
            CallGraph.Edge(from: "b.c:b_entry(int)", to: "b.c:helper(int)", weight: 1)))
        #expect(!graph.edges.contains(
            CallGraph.Edge(from: "a.c:a_entry(int)", to: "b.c:helper(int)", weight: 1)))
    }

    /// Two nodes that would otherwise draw the same label say which file they came from; a node with
    /// no namesake keeps its bare name, so an ordinary diagram reads exactly as it did before.
    @Test func onlyACollidingFreeFunctionShowsItsFileInTheLabel() {
        let left = CCodeParser().parse(source: """
        static int helper(int n) { return n; }
        int a_entry(int n) { return helper(n); }
        """, fileName: "a.c")
        let right = CCodeParser().parse(source: """
        static int helper(int n) { return n + 1; }
        int b_entry(int n) { return helper(n); }
        """, fileName: "b.c")
        let graph = CallGraphBuilder().build(from: left.merging(with: right).resolvingCallSiteReceivers())

        #expect(graph.nodes.filter { $0.methodName == "helper" }.map(\.label).sorted()
            == ["a.c.helper(int)", "b.c.helper(int)"])
        #expect(graph.nodes.first { $0.methodName == "a_entry" }?.label == "a_entry")
    }
}
