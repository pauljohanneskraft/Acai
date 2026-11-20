import Testing
import AcaiCore
@testable import AcaiLibrary

/// Every parser records what a call passes (``CallSite/arguments``), which is what lets the call
/// graph pick one overload out of a set. Arity is what each language owes; a label is recorded only
/// by the languages that spell one, and `CallSiteSyntax.callArguments(of:)` has to find the argument
/// list wherever that language's grammar hangs it — Kotlin off a `call_suffix`, Dart off a trailing
/// `selector` — so each is pinned here.
@Suite("Call argument capture")
struct CallArgumentCaptureTests {

    private func arguments(of artifact: CodeArtifact) -> [[String?]?] {
        artifact.types.flatMap { $0.members }.flatMap { $0.callSites }.map(\.arguments)
    }

    @Test func swiftRecordsLabelsAndCountsATrailingClosure() {
        let artifact = SwiftCodeParser().parse(source: """
        class Widget {
            func use() {
                render(text: "a", times: 2)
                render("b")
                load { _ in }
            }
            func render(text: String, times: Int) {}
            func render(_ text: String) {}
            func load(then: (Int) -> Void) {}
        }
        """, fileName: "w.swift")
        #expect(arguments(of: artifact) == [["text", "times"], [nil], [nil]])
    }

    @Test func kotlinRecordsNamedArgumentLabels() {
        let artifact = KotlinCodeParser().parse(source: """
        class Widget {
            fun use() { render(text = "a", times = 2); render("b") }
            fun render(text: String, times: Int) {}
            fun render(text: String) {}
        }
        """, fileName: "w.kt")
        #expect(arguments(of: artifact) == [["text", "times"], [nil]])
    }

    /// A positional Kotlin argument that is itself a bare identifier is a `simple_identifier` child
    /// of its `value_argument`, exactly where a label sits — so only the `=` distinguishes them.
    @Test func aPositionalKotlinIdentifierArgumentIsNotMistakenForALabel() {
        let artifact = KotlinCodeParser().parse(source: """
        class Widget {
            fun use(other: String) { render(other) }
            fun render(text: String) {}
        }
        """, fileName: "w.kt")
        #expect(arguments(of: artifact) == [[nil]])
    }

    @Test func dartRecordsNamedArgumentLabels() {
        let artifact = DartCodeParser().parse(source: """
        class Widget {
          void use() { render(text: "a", times: 2); plain("b"); }
          void render({String text, int times}) {}
          void plain(String t) {}
        }
        """, fileName: "w.dart")
        #expect(arguments(of: artifact) == [["text", "times"], [nil]])
    }

    /// Java, TypeScript, Python, C and C++ have no argument labels, so what they owe is the count —
    /// found through the shared `arguments` field their grammars all expose.
    @Test func theLanguagesWithoutLabelsStillRecordTheCount() {
        let java = JavaCodeParser().parse(source: """
        class Widget {
            void use() { render("a", 2); render(); }
            void render(String text, int times) {}
            void render() {}
        }
        """, fileName: "Widget.java")
        #expect(arguments(of: java) == [[nil, nil], []])

        let typeScript = JSCodeParser().parse(source: """
        class Widget {
            use() { this.render("a", 2); this.render(); }
            render(text?: string, times?: number) {}
        }
        """, fileName: "w.ts")
        #expect(arguments(of: typeScript) == [[nil, nil], []])

        let python = PythonCodeParser().parse(source: """
        class Widget:
            def use(self):
                self.render("a", 2)
                self.render()
            def render(self, text=None, times=1): pass
        """, fileName: "w.py")
        #expect(arguments(of: python) == [[nil, nil], []])
    }

    @Test func cRecordsTheCountOfAFreeFunctionCall() {
        let artifact = CCodeParser().parse(source: """
        static int helper(int n, int m) { return n + m; }
        int entry(int n) { return helper(n, 1); }
        """, fileName: "a.c")
        #expect(artifact.freestandingFunctions.flatMap { $0.callSites }.map(\.arguments) == [[nil, nil]])
    }
}
