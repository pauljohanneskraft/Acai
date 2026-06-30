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
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                guard let json = String(data: try encoder.encode(diff), encoding: .utf8) else {
                    throw ValidationError("Failed to encode diff as JSON.")
                }
                return json
            }
        }

        /// Dispatches to the requested diagram type's delta renderer. Each builds the type's diagram
        /// model from both revisions, diffs the two models, and renders the union with added=green/
        /// removed=red/changed=amber via the gated per-element colour overrides.
        private func deltaDiagram(old: CodeArtifact, new: CodeArtifact, format: FormatOption) throws -> String {
            if let sequenceFrom {
                return try sequenceDelta(old: old, new: new, entry: sequenceFrom, format: format)
            } else if let stateFrom {
                return try stateDelta(old: old, new: new, variable: stateFrom, format: format)
            } else if package {
                return packageDelta(old: old, new: new, format: format)
            } else if callGraph {
                return try callGraphDelta(old: old, new: new, format: format)
            }
            return classDelta(old: old, new: new, format: format)
        }

        private func classDelta(old: CodeArtifact, new: CodeArtifact, format: FormatOption) -> String {
            let differ = ArtifactDiffer()
            let diff = differ.diff(old: old, new: new)
            let edgeStatus = diff.relationshipStatusLookup()
            let typeStatus = diff.typeStatusLookup()
            let options = ClassDiagramOptions(
                showExternalTypes: true,
                language: new.standardLanguageConfiguration,
                edgeColorOverride: { edgeStatus($0).deltaHex },
                nodeColorOverride: { typeStatus($0.id).deltaHex }
            )
            let union = differ.unionArtifact(old: old, new: new)
            switch format {
            case .dot:
                return ClassDiagramDOTRenderer(options: options).generate(from: union)
            case .mermaid:
                return ClassDiagramMermaidRenderer(options: options).generate(from: union)
            }
        }

        private func sequenceDelta(
            old: CodeArtifact, new: CodeArtifact, entry: String, format: FormatOption
        ) throws -> String {
            let entryPoint = try parseSequenceEntryPoint(entry)
            let oldDiagram = old.sequenceDiagram(entryPoint: entryPoint, maxDepth: maxDepth)
            let newDiagram = new.sequenceDiagram(entryPoint: entryPoint, maxDepth: maxDepth)
            let diff = SequenceDiagramDiff(old: oldDiagram, new: newDiagram)
            switch format {
            case .dot:
                return SequenceDiagramDOTRenderer(
                    messageColor: { diff.status(of: $0).deltaHex }
                ).render(diff.union)
            case .mermaid:
                // Mermaid sequence syntax has no per-message colour; render the union uncolored.
                return SequenceDiagramMermaidRenderer().render(diff.union)
            }
        }

        private func stateDelta(
            old: CodeArtifact, new: CodeArtifact, variable: String, format: FormatOption
        ) throws -> String {
            let configuration = try StateDiagramConfiguration(stateFrom: variable, maxStates: maxStates)
            let oldDiagram = try old.resolvingExtensions().stateDiagram(configuration: configuration)
            let newDiagram = try new.resolvingExtensions().stateDiagram(configuration: configuration)
            let diff = StateDiagramDiff(old: oldDiagram, new: newDiagram)
            switch format {
            case .dot:
                return StateDiagramDOTRenderer(
                    transitionColor: { diff.status(of: $0).deltaHex }
                ).render(diff.union)
            case .mermaid:
                // Mermaid state syntax has no per-transition colour; render the union uncolored.
                return StateDiagramMermaidRenderer().render(diff.union)
            }
        }

        private func packageDelta(old: CodeArtifact, new: CodeArtifact, format: FormatOption) -> String {
            let oldDiagram = old.enriched(configuration: old.standardLanguageConfiguration).packageDependencyDiagram()
            let newDiagram = new.enriched(configuration: new.standardLanguageConfiguration).packageDependencyDiagram()
            let diff = PackageDiagramDiff(old: oldDiagram, new: newDiagram)
            let nodeColor: @Sendable (String) -> String? = { diff.status(ofNode: $0).deltaHex }
            let edgeColor: @Sendable (String, String) -> String? = {
                diff.status(ofEdgeFrom: $0, to: $1).deltaHex
            }
            switch format {
            case .dot:
                return PackageDiagramDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            case .mermaid:
                return PackageDiagramMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            }
        }

        private func callGraphDelta(
            old: CodeArtifact, new: CodeArtifact, format: FormatOption
        ) throws -> String {
            let scope = try parseCallGraphScope()
            let diff = CallGraphDiff(old: old.callGraph(scope: scope), new: new.callGraph(scope: scope))
            let nodeColor: @Sendable (String) -> String? = { diff.status(ofNode: $0).deltaHex }
            let edgeColor: @Sendable (String, String) -> String? = {
                diff.status(ofEdgeFrom: $0, to: $1).deltaHex
            }
            switch format {
            case .dot:
                return CallGraphDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            case .mermaid:
                return CallGraphMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            }
        }

        /// Parses `--call-graph-scope` (`"type:Name"` / `"module:Name"`) into a `CallGraphScope`.
        private func parseCallGraphScope() throws -> CallGraphScope {
            guard let raw = callGraphScope else { return .wholeCodebase }
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].isEmpty else {
                throw ValidationError("--call-graph-scope must be \"type:Name\" or \"module:Name\".")
            }
            switch parts[0] {
            case "type":
                return .type(parts[1])
            case "module":
                return .module(parts[1])
            default:
                throw ValidationError("--call-graph-scope must start with \"type:\" or \"module:\".")
            }
        }
    }
}
