import Foundation
import Testing
@testable import AcaiCLI

/// Exercises `GraphvizSVGRenderer` against small fake `dot` scripts rather than a real Graphviz
/// install, so these tests are deterministic regardless of whether Graphviz is on the machine.
@Suite("Graphviz SVG Renderer")
struct GraphvizSVGRendererTests {

    private func writeFakeDot(in directory: URL, script: String) throws -> URL {
        let url = directory.appendingPathComponent("dot")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func renderSVGReturnsGraphvizOutput() throws {
        try CLITestSupport.withTempDirectory { dir in
            let dot = try writeFakeDot(in: dir, script: """
            #!/bin/sh
            # args: -Tsvg <input> -o <output>
            { echo '<svg xmlns="http://www.w3.org/2000/svg">'; cat "$2"; echo '</svg>'; } > "$4"
            """)
            let renderer = GraphvizSVGRenderer(executableURL: dot)
            let svg = try renderer.renderSVG(fromDOT: "digraph FakeGraph {}")
            #expect(svg.contains("<svg"))
            #expect(svg.contains("digraph FakeGraph"))
        }
    }

    @Test func renderSVGThrowsWithStderrOnNonZeroExit() throws {
        try CLITestSupport.withTempDirectory { dir in
            let dot = try writeFakeDot(in: dir, script: """
            #!/bin/sh
            echo "syntax error in line 1" >&2
            exit 1
            """)
            let renderer = GraphvizSVGRenderer(executableURL: dot)
            #expect {
                try renderer.renderSVG(fromDOT: "not actually dot")
            } throws: { error in
                (error as? GraphvizRenderError)?.message == "syntax error in line 1"
            }
        }
    }

    @Test func initSearchesPathAndFindsExecutable() throws {
        try CLITestSupport.withTempDirectory { dir in
            _ = try writeFakeDot(in: dir, script: """
            #!/bin/sh
            echo '<svg></svg>' > "$4"
            """)
            let renderer = try GraphvizSVGRenderer(searchPaths: [dir.path])
            #expect(renderer.executableURL.path == dir.appendingPathComponent("dot").path)
        }
    }

    @Test func initThrowsWhenNotFoundOnPath() throws {
        try CLITestSupport.withTempDirectory { dir in
            #expect(throws: GraphvizNotFoundError.self) {
                try GraphvizSVGRenderer(searchPaths: [dir.path])
            }
        }
    }
}
