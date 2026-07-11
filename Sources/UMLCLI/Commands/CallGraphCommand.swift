import ArgumentParser
import UMLDiagram
import UMLLibrary

extension UMLCommand {
    /// Three cuts of the one static call graph, selected by `--mode`: `metrics` (per-method
    /// fan-in/out, recursion, coverage), `cycles` (method-level mutual-recursion clusters), and
    /// `deadcode` (uncalled, non-entry-point method candidates). All share the same call-graph build.
    struct CallGraph: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "callgraph",
            abstract: "Call-graph analysis: metrics, method cycles, or dead-code candidates"
        )

        enum Mode: String, ExpressibleByArgument, CaseIterable {
            case metrics
            case cycles
            case deadcode
        }

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "What to report: metrics (default), cycles, or deadcode.")
        var mode: Mode = .metrics

        @Option(name: .long, help: ArgumentHelp(
            "Scope (metrics/cycles): \"type:Name\" or \"module:Name\". Whole codebase if omitted."))
        var scope: String?

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Limit the human metrics table to the top N hottest methods.")
        var top: Int?

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        @Flag(name: .long, help: "In cycles mode, exit 0 even when call cycles are found (don't fail CI).")
        var noFail = false

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
            switch mode {
            case .metrics:
                try renderMetrics(artifact)
            case .cycles:
                try renderCycles(artifact)
            case .deadcode:
                try renderDeadCode(artifact)
            }
        }

        // MARK: - metrics

        private func renderMetrics(_ artifact: CodeArtifact) throws {
            let callScope = try CallGraphScopeOption(raw: scope).resolved()
            let report = CallGraphMetrics(artifact: artifact, scope: callScope).report
            let rendered = format == .json ? try JSONReport(report).text : metricsHuman(report)
            try rendered.writeOutput(to: output, label: "call graph")
        }

        private func metricsHuman(_ report: UMLDiagram.CallGraphMetrics.Report) -> String {
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

        // MARK: - cycles

        private func renderCycles(_ artifact: CodeArtifact) throws {
            let callScope = try CallGraphScopeOption(raw: scope).resolved()
            let clusters = MethodCycles(artifact: artifact, scope: callScope).clusters
            let rendered = format == .json ? try JSONReport(clusters).text : cyclesHuman(clusters)
            try rendered.writeOutput(to: output, label: "call cycles")
            if !clusters.isEmpty && !noFail { throw ExitCode.failure }
        }

        private func cyclesHuman(_ clusters: [MethodCycles.Cluster]) -> String {
            guard !clusters.isEmpty else { return "No method-level call cycles found.\n" }
            var lines = ["Found \(clusters.count) method-level call cycle(s):"]
            for cluster in clusters {
                let ids = cluster.methods.map(\.id).joined(separator: " → ")
                lines.append("  \(ids)")
            }
            return lines.joined(separator: "\n") + "\n"
        }

        // MARK: - deadcode

        private func renderDeadCode(_ artifact: CodeArtifact) throws {
            let report = DeadCodeScan(
                artifact: artifact,
                languages: artifact.standardLanguageResolver).report
            let rendered = format == .json ? try JSONReport(report).text : deadCodeHuman(report)
            try rendered.writeOutput(to: output, label: "dead code")
        }

        private func deadCodeHuman(_ report: DeadCodeScan.Report) -> String {
            let coverage = Int((report.coverage.fraction * 100).rounded())
            guard !report.candidates.isEmpty else {
                return "No dead-code candidates (call-graph coverage \(coverage)%).\n"
            }
            var lines = [
                "\(report.candidates.count) dead-code candidate(s) "
                + "— call-graph coverage \(coverage)% (candidates below this floor may be false positives):"
            ]
            for candidate in report.candidates {
                lines.append("  \(candidate.id)\(candidate.location.suffix)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
