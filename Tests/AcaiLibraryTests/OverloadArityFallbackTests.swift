import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

@Suite("Overload arity fallback")
struct OverloadArityFallbackTests {

    private func deadIDs(_ artifact: CodeArtifact) -> [String] {
        DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver).report.candidates.map(\.id)
    }

    @Test func aDartCallOmittingAnOptionalParameterKeepsTheCalleeLive() {
        let artifact = DartCodeParser().parse(source: """
        class Widget {
          void use() { _render(1); }
          void _render(int a, [int b = 0]) {}
        }
        """, fileName: "widget.dart")
        #expect(!deadIDs(artifact).contains { $0.contains("_render") })
    }

    @Test func aDartCallOmittingANamedParameterKeepsTheCalleeLive() {
        let artifact = DartCodeParser().parse(source: """
        class Widget {
          void use() { _render(1); }
          void _render(int a, {int b = 0}) {}
        }
        """, fileName: "widget.dart")
        #expect(!deadIDs(artifact).contains { $0.contains("_render") })
    }

    @Test func aCppCallOmittingADefaultArgumentKeepsTheCalleeLive() {
        let artifact = CppCodeParser().parse(source: """
        class Widget {
        public:
            void use() { render(1); }
        private:
            void render(int a, int b = 0) {}
        };
        """, fileName: "widget.cpp")
        #expect(!deadIDs(artifact).contains { $0.contains("render") })
    }

    @Test func aKotlinTrailingLambdaCountsAsAnArgument() {
        let artifact = KotlinCodeParser().parse(source: """
        class Widget {
            fun use() { render(1) { } }
            private fun render(a: Int) {}
            private fun render(a: Int, block: () -> Unit) {}
        }
        """, fileName: "Widget.kt")
        let dead = deadIDs(artifact)
        #expect(dead == ["Widget.render(Int)"])
    }

    @Test func aPythonMethodCallReachesItsMethod() {
        let artifact = PythonCodeParser().parse(source: """
        class Widget:
            def use(self):
                self._render(1)

            def _render(self, a):
                pass
        """, fileName: "widget.py")
        #expect(!deadIDs(artifact).contains { $0.contains("_render") })
    }

    @Test func aJavaScriptCallPassingFewerArgumentsKeepsTheCalleeLive() {
        let artifact = JSCodeParser().parse(source: """
        class Widget {
          use() { this.render(1); }
          render(a, b) {}
        }
        """, fileName: "widget.js")
        #expect(!deadIDs(artifact).contains { $0.contains("render") })
    }
}
