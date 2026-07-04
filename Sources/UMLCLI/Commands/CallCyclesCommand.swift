import ArgumentParser
import UMLDiagram
import UMLLibrary

extension UMLCommand {
    /// Reports method-level call cycles (mutual recursion / tangled method clusters) — the
    /// strongly-connected components of the call graph — each member with its `file:line`.
    struct CallCycles: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "call-cycles",
            abstract: "Detect method-level call cycles (mutual recursion) as JSON/human"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Scope: \"type:Name\" or \"module:Name\". Whole codebase if omitted.")
        var scope: String?

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        @Flag(name: .long, help: "Exit 0 even when call cycles are found (don't fail CI).")
        var noFail = false

        mutating func validate() throws {
            try artifactSource.validate()
            _ = try CallGraphScopeOption(raw: scope).resolved()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let callScope = try CallGraphScopeOption(raw: scope).resolved()
            let clusters = MethodCycles(artifact: artifact, scope: callScope).clusters

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(clusters).text
            case .human:
                rendered = humanReport(clusters)
            }
            try rendered.writeOutput(to: output, label: "call cycles")

            if !clusters.isEmpty && !noFail { throw ExitCode.failure }
        }

        private func humanReport(_ clusters: [MethodCycles.Cluster]) -> String {
            guard !clusters.isEmpty else { return "No method-level call cycles found.\n" }
            var lines = ["Found \(clusters.count) method-level call cycle(s):"]
            for cluster in clusters {
                let ids = cluster.methods.map(\.id).joined(separator: " → ")
                lines.append("  \(ids)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
