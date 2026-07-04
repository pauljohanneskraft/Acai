import ArgumentParser
import Foundation
import UMLCore
import UMLDiagram
import UMLDiff
import UMLLibrary

extension UMLCommand {
    struct Diff: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the structural delta between two revisions of a codebase",
            discussion: """
            Compares an OLD and a NEW artifact and reports only what structurally changed — added/\
            removed types, added/removed/changed relationships, and notable metric movement.

            Each side is either a stored analysis name / .json path (positional), or a source \
            directory to analyze on the fly (--source-old / --source-new):

              uml diff main-baseline HEAD-analysis
              uml diff old.json new.json
              uml diff main-baseline --source-new ./
            """
        )

        @Argument(help: "Old side: a stored analysis name or a path to a .json file.")
        var old: String?

        @Argument(help: "New side: a stored analysis name or a path to a .json file.")
        var new: String?

        @Option(name: .long, help: "Analyze this source directory as the OLD side instead of a stored artifact.")
        var sourceOld: String?

        @Option(name: .long, help: "Analyze this source directory as the NEW side instead of a stored artifact.")
        var sourceNew: String?

        @Option(name: .long, help: ArgumentHelp(
            "Limit on-the-fly analysis to one or more languages (\(LanguageOption.allValuesList))."
        ))
        var language: [LanguageOption] = []

        @Option(name: .long, help: "Report format: human or json.")
        var format: ReportFormatOption = .human

        @Option(name: .long, help: ArgumentHelp(
            "Render a delta diagram (dot or mermaid) with added/removed/changed elements colour-coded,"
            + " instead of a textual report. Defaults to a class diagram; combine with one of"
            + " --sequence-from / --state-from / --package / --call-graph for the other diagram types."
        ))
        var diagram: FormatOption?

        @Option(name: .long, help: "Delta a sequence diagram traced from this entry point (\"Type.method\").")
        var sequenceFrom: String?

        @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
        var maxDepth: Int = 5

        @Option(name: .long, help: "Delta a value-flow state diagram for this variable (\"Type.variable\").")
        var stateFrom: String?

        @Option(name: .long, help: "Maximum number of distinct states before the analysis fails.")
        var maxStates: Int = 20

        @Flag(name: .long, help: "Delta a package/module dependency diagram.")
        var package = false

        @Flag(name: .long, help: "Delta a static call graph.")
        var callGraph = false

        @Option(name: .long, help: "Scope the call-graph delta (\"type:Name\" or \"module:Name\").")
        var callGraphScope: String?

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try Self.validateSide(name: "old", ref: old, source: sourceOld)
            try Self.validateSide(name: "new", ref: new, source: sourceNew)
            let modeFlags = [sequenceFrom != nil, stateFrom != nil, package, callGraph].filter { $0 }.count
            if modeFlags > 1 {
                throw ValidationError(
                    "Specify only one of --sequence-from, --state-from, --package, or --call-graph.")
            }
            if modeFlags > 0 && diagram == nil {
                throw ValidationError("A diagram-type flag requires --diagram dot|mermaid.")
            }
            if callGraphScope != nil && !callGraph {
                throw ValidationError("--call-graph-scope requires --call-graph.")
            }
            try DiagramLimits().validate(maxDepth: maxDepth, maxStates: maxStates)
        }

        private static func validateSide(name: String, ref: String?, source: String?) throws {
            if ref == nil && source == nil {
                throw ValidationError("Specify the \(name) side: a positional artifact or --source-\(name).")
            }
            if ref != nil && source != nil {
                throw ValidationError(
                    "For the \(name) side, give either a positional artifact or --source-\(name), not both.")
            }
        }

        mutating func run() throws {
            let oldArtifact = try ArtifactSource.resolve(from: old, source: sourceOld, language: language)
            let newArtifact = try ArtifactSource.resolve(from: new, source: sourceNew, language: language)

            let rendered: String
            if let diagram {
                rendered = try deltaDiagram(old: oldArtifact, new: newArtifact, format: diagram)
            } else {
                rendered = try report(for: ArtifactDiffer().diff(old: oldArtifact, new: newArtifact))
            }
            try rendered.writeOutput(to: output, label: "diff")
        }

        private func report(for diff: ArtifactDiff) throws -> String {
            switch format {
            case .human:
                return diff.humanReport()
            case .json:
                return try JSONReport(diff).text
            }
        }

        /// Dispatches to the requested diagram type's delta exporter. Each builds the type's diagram
        /// model from both revisions, diffs the two models, and renders the union with added=green/
        /// removed=red/changed=amber via the gated per-element colour overrides.
        private func deltaDiagram(old: CodeArtifact, new: CodeArtifact, format: FormatOption) throws -> String {
            let diagramFormat = format.diagramFormat
            if let sequenceFrom {
                return try SequenceDeltaExporter(
                    request: SequenceDiagramRequest(entryPoint: sequenceFrom, maxDepth: maxDepth)
                ).render(old: old, new: new, format: diagramFormat)
            } else if let stateFrom {
                return try StateDeltaExporter(
                    request: StateDiagramRequest(variable: stateFrom, maxStates: maxStates)
                ).render(old: old, new: new, format: diagramFormat)
            } else if package {
                return PackageDeltaExporter().render(old: old, new: new, format: diagramFormat)
            } else if callGraph {
                return try CallGraphDeltaExporter(
                    request: CallGraphRequest(scope: CallGraphScopeOption(raw: callGraphScope))
                ).render(old: old, new: new, format: diagramFormat)
            }
            return ClassDeltaExporter().render(old: old, new: new, format: diagramFormat)
        }
    }
}
