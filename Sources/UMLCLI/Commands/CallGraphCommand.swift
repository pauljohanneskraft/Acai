import ArgumentParser
import UMLDiagram
import UMLLibrary

extension UMLCommand {
    /// Reports the static call graph as metrics rather than a diagram: per-method fan-in/fan-out,
    /// recursion, and the graph's resolution coverage, ranked hottest-first.
    struct CallGraph: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "callgraph",
            abstract: "Call-graph metrics (fan-in/out, recursion, coverage) as JSON/human"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Scope: \"type:Name\" or \"module:Name\". Whole codebase if omitted.")
        var scope: String?

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Limit the human table to the top N hottest methods.")
        var top: Int?

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
            // Surface a malformed --scope as a usage error (exit 64), mapping the diagram layer's error.
            do {
                _ = try CallGraphScopeOption(raw: scope).resolved()
            } catch let error as DiagramRequestError {
                throw ValidationError(error.message)
            }
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let callScope = try CallGraphScopeOption(raw: scope).resolved()
            let report = CallGraphMetrics(artifact: artifact, scope: callScope).report

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(report).text
            case .human:
                rendered = humanReport(report)
            }
            try rendered.writeOutput(to: output, label: "call graph")
        }

        private func humanReport(_ report: UMLDiagram.CallGraphMetrics.Report) -> String {
            let coverage = Int((report.coverage.fraction * 100).rounded())
            var lines = [
                "Call graph: \(report.nodeCount) method(s), \(report.edgeCount) edge(s), "
                + "\(coverage)% resolved."
            ]
            let rows = top.map { Array(report.nodes.prefix($0)) } ?? report.nodes
            for node in rows {
                let recursion = node.isRecursive ? " (recursive)" : ""
                lines.append(
                    "  \(node.label): in \(node.fanIn), out \(node.fanOut)\(recursion)\(node.location.suffix)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
