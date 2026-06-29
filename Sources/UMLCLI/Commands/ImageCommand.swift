#if os(macOS)
import ArgumentParser
import CoreGraphics
import Foundation
import SwiftUI
import UMLDiagram
import UMLDiff
import UMLLibrary
import UMLRender

extension UMLCommand {
    /// Renders a class diagram to a PNG image using the same SwiftUI views and layout engine
    /// as the macOS app (via `UMLRender`), rather than going through DOT/Graphviz.
    ///
    /// macOS-only: image rendering relies on SwiftUI's `ImageRenderer`, which needs a GUI /
    /// window-server session. On other platforms this subcommand is not registered.
    struct Image: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Render a class diagram to a PNG image (macOS only)"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Output PNG file path.")
        var output: String

        @Option(name: .long, help: "Old side for a delta image: a source directory to analyze.")
        var sourceOld: String?

        @Option(name: .long, help: "Old side for a delta image: a stored analysis name or .json path.")
        var fromOld: String?

        @Option(name: .long, help: "Grouping strategy: none, directory, product.")
        var grouping: ClassDiagramConfiguration.Grouping = .product

        @Option(name: .long, help: ArgumentHelp(
            "Only show members (and whole types) at or above this access level:" +
            " open, public, packagePrivate, internal, protected, filePrivate, private."
        ))
        var minAccess: AccessLevel?

        @Flag(name: .long, help: "Hide type members (properties and methods).")
        var hideMembers: Bool = false

        @Option(name: .long, help: "Output resolution scale factor.")
        var scale: Double = 2

        @Option(name: .long, help: "Colour theme for the rendered image: default (light) or dark.")
        var theme: ThemeOption = .default

        /// The render palette for the selected `--theme`.
        private var palette: DiagramPalette {
            theme == .dark ? .dark : .light
        }

        @Option(name: .long, help: ArgumentHelp(
            "Render a sequence diagram traced from this entry point instead of a class diagram." +
            " Format: \"TypeName.methodName\", or \"functionName\" for a top-level function."
        ))
        var sequenceFrom: String?

        @Option(name: .long, help: ArgumentHelp(
            "Resolve an interface/protocol to a concrete type when tracing a sequence diagram." +
            " Repeat for multiple: --map Protocol=Concrete --map Other=Impl."
        ))
        var map: [String] = []

        @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
        var maxDepth: Int = 5

        @Option(name: .long, help: ArgumentHelp(
            "Render a value-flow state diagram for this variable instead of a class diagram." +
            " Format: \"TypeName.variableName\", or just \"variableName\" for a global."
        ))
        var stateFrom: String?

        @Option(name: .long, help: "Maximum number of distinct states before the analysis fails.")
        var maxStates: Int = 20

        @Flag(name: .long, help: "Render a package/module dependency diagram instead of a class diagram.")
        var package: Bool = false

        @Flag(name: .long, help: "Render a static call graph instead of a class diagram.")
        var callGraph: Bool = false

        @Option(name: .long, help: ArgumentHelp(
            "Scope the call graph to a single type or build module:"
            + " \"type:Name\" or \"module:Name\". Defaults to the whole codebase."
        ))
        var callGraphScope: String?

        @Option(name: .long, help: ArgumentHelp(
            "Focus the class diagram on a single type, showing only the subgraph around it."
            + " Pass the type name."
        ))
        var focus: String?

        @Option(name: .long, help: ArgumentHelp(
            "Maximum focus traversal depth (1 = the type plus its direct neighbours)."
            + " Omit for unlimited."
        ))
        var focusDepth: Int?

        @Option(name: .long, help: "Focus traversal direction: dependencies, dependents, both.")
        var focusDirection: FocusDirectionOption?

        @Option(name: .long, help: ArgumentHelp(
            "Restrict focus to one or more relationship kinds (e.g. inheritance)."
            + " Repeat the flag for multiple. Defaults to all kinds."
        ))
        var focusRelationship: [RelationshipKindOption] = []

        @Flag(name: .long, help: ArgumentHelp(
            "When focusing, draw only the edges actually walked, not every edge among the"
            + " selected types."
        ))
        var noFocusInterconnections: Bool = false

        mutating func validate() throws {
            try artifactSource.validate()
            let modeFlags = [sequenceFrom != nil, stateFrom != nil, package, callGraph].filter { $0 }.count
            if modeFlags > 1 {
                throw ValidationError(
                    "Specify only one of --sequence-from, --state-from, --package, or --call-graph."
                )
            }
            if callGraphScope != nil && !callGraph {
                throw ValidationError("--call-graph-scope requires --call-graph.")
            }
            try DiagramLimitBounds.validate(maxDepth: maxDepth, maxStates: maxStates)
        }

        /// The "old" side for a delta image, when `--source-old` / `--from-old` is given.
        private func resolveOldArtifact() throws -> CodeArtifact? {
            guard fromOld != nil || sourceOld != nil else { return nil }
            return try ArtifactSource.resolve(from: fromOld, source: sourceOld, language: artifactSource.language)
        }

        mutating func run() async throws {
            let artifact = try artifactSource.resolve()
            let oldArtifact = try resolveOldArtifact()

            let data: Data
            if let oldArtifact, sequenceFrom == nil, stateFrom == nil, !package, !callGraph {
                data = try await renderClassDelta(old: oldArtifact, new: artifact)
            } else if let sequenceFrom {
                if let oldArtifact {
                    data = try await renderSequenceDelta(old: oldArtifact, new: artifact, entryPoint: sequenceFrom)
                } else {
                    data = try await renderSequence(artifact: artifact, entryPoint: sequenceFrom)
                }
            } else if let stateFrom {
                if let oldArtifact {
                    data = try await renderStateDelta(old: oldArtifact, new: artifact, variable: stateFrom)
                } else {
                    data = try await renderState(artifact: artifact, variable: stateFrom)
                }
            } else if package, let oldArtifact {
                data = try await renderPackageDelta(old: oldArtifact, new: artifact)
            } else if package {
                let diagram = artifact.enriched(configuration: artifact.standardLanguageConfiguration)
                    .packageDependencyDiagram()
                let renderScale = CGFloat(scale)
                data = try await MainActor.run {
                    try DiagramImageRenderer.renderPNG(packageDiagram: diagram, scale: renderScale, palette: palette)
                }
            } else if callGraph, let oldArtifact {
                data = try await renderCallGraphDelta(old: oldArtifact, new: artifact)
            } else if callGraph {
                data = try await renderCallGraph(artifact: artifact)
            } else {
                data = try await renderClassDiagram(artifact: artifact)
            }

            let outputURL = URL(fileURLWithPath: output)
            try data.write(to: outputURL, options: .atomic)
            print("Wrote image to \(output)")
        }

        /// The class-diagram configuration derived from the grouping/access/member/focus flags,
        /// shared by the plain and delta render paths so they honour the same options.
        private func classDiagramConfiguration() -> ClassDiagramConfiguration {
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = grouping
            configuration.minimumAccessLevel = minAccess
            if hideMembers {
                configuration.showProperties = false
                configuration.showMethods = false
            }
            configuration.focus = FocusOptionBuilder.make(
                rootTypeName: focus,
                depth: focusDepth,
                direction: focusDirection,
                relationshipKinds: focusRelationship,
                includeInterconnections: !noFocusInterconnections
            )
            return configuration
        }

        /// Renders the plain (non-delta) class diagram to PNG from the flags/focus options.
        private func renderClassDiagram(artifact: CodeArtifact) async throws -> Data {
            let configuration = classDiagramConfiguration()
            let language = artifact.standardLanguageConfiguration
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(
                    artifact: artifact,
                    configuration: configuration,
                    language: language,
                    scale: CGFloat(scale),
                    palette: palette
                )
            }
        }

        /// Renders the class-diagram delta of two revisions to PNG: the union diagram with each edge
        /// tinted by its diff status (added green / removed red / changed amber).
        private func renderClassDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
            let differ = ArtifactDiffer()
            let diff = differ.diff(old: old, new: new)
            let union = differ.unionArtifact(old: old, new: new)
            let edgeStatus = diff.relationshipStatusLookup()
            let typeStatus = diff.typeStatusLookup()
            let edgeColor: @Sendable (GeneratedDiagramEdge) -> Color? = { edge in
                edgeStatus(Relationship(kind: edge.kind, source: edge.sourceID, target: edge.targetID)).deltaColor
            }
            let nodeColor: @Sendable (GeneratedDiagramNode) -> Color? = { typeStatus($0.id).deltaColor }
            let configuration = classDiagramConfiguration()
            let language = union.standardLanguageConfiguration
            let renderScale = CGFloat(scale)
            let renderPalette = palette
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(
                    artifact: union, configuration: configuration, language: language,
                    scale: renderScale, palette: renderPalette, edgeColor: edgeColor, nodeColor: nodeColor)
            }
        }

        /// Renders the package-diagram delta of two revisions to PNG: the union with each module
        /// node and dependency edge tinted by its diff status.
        private func renderPackageDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
            let oldDiagram = old.enriched(configuration: old.standardLanguageConfiguration).packageDependencyDiagram()
            let newDiagram = new.enriched(configuration: new.standardLanguageConfiguration).packageDependencyDiagram()
            let diff = PackageDiagramDiff(old: oldDiagram, new: newDiagram)
            let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
            let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
            let renderScale = CGFloat(scale)
            let renderPalette = palette
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(
                    packageDiagram: diff.union, scale: renderScale, palette: renderPalette,
                    nodeColor: nodeColor, edgeColor: edgeColor)
            }
        }

        /// Renders the call-graph delta of two revisions to PNG: the union with each method node and
        /// call edge tinted by its diff status.
        private func renderCallGraphDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
            let scope = try parseCallGraphScope()
            let diff = CallGraphDiff(old: old.callGraph(scope: scope), new: new.callGraph(scope: scope))
            let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
            let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
            let renderScale = CGFloat(scale)
            let renderPalette = palette
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(
                    callGraph: diff.union, scale: renderScale, palette: renderPalette,
                    nodeColor: nodeColor, edgeColor: edgeColor)
            }
        }

        /// Traces a sequence diagram from `entryPoint` ("Type.method", or a bare top-level function
        /// name) and renders it to PNG.
        private func renderSequence(artifact: CodeArtifact, entryPoint: String) async throws -> Data {
            let (typeName, methodName) = try parseSequenceEntryPoint(entryPoint)

            var typeMapping: [String: String] = [:]
            for entry in map {
                let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw ValidationError("--map must be in the form \"Protocol=Concrete\".")
                }
                typeMapping[parts[0]] = parts[1]
            }

            let diagram = artifact.sequenceDiagram(
                entryPoint: (typeName, methodName),
                maxDepth: maxDepth,
                typeMapping: typeMapping
            )
            guard !diagram.participants.isEmpty else {
                throw ValidationError(
                    "No calls could be traced from \(entryPoint). Sequence diagrams follow "
                    + "explicitly-typed property receivers; try another entry point or --map."
                )
            }
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(sequenceDiagram: diagram, scale: CGFloat(scale), palette: palette)
            }
        }

        /// Builds a static call graph (optionally scoped) and renders it to PNG.
        private func renderCallGraph(artifact: CodeArtifact) async throws -> Data {
            let scope = try parseCallGraphScope()
            let graph = artifact.callGraph(scope: scope)
            guard !graph.edges.isEmpty else {
                throw ValidationError(
                    "No resolvable calls found for the requested scope. Call graphs follow "
                    + "explicitly-typed call receivers; try a wider scope or another language."
                )
            }
            let renderScale = CGFloat(scale)
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(callGraph: graph, scale: renderScale, palette: palette)
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

        /// Runs the value-flow state analysis for `variable` and renders the diagram to PNG.
        private func renderState(artifact: CodeArtifact, variable: String) async throws -> Data {
            let configuration = try StateVariableSpec.configuration(from: variable, maxStates: maxStates)
            let diagram: StateDiagram
            do {
                diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
            } catch let error as StateDiagramAnalysisError {
                throw ValidationError(error.message)
            }
            let renderScale = CGFloat(scale)
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(stateDiagram: diagram, scale: renderScale, palette: palette)
            }
        }

    }
}

extension UMLCommand.Image {
    /// Renders the sequence-diagram delta of two revisions to PNG: the union trace with each message
    /// tinted by its diff status. Messages are coloured by their layout id, which equals the
    /// message's position in the (order-sorted) union.
    func renderSequenceDelta(
        old: CodeArtifact, new: CodeArtifact, entryPoint: String
    ) async throws -> Data {
        let entry = try parseSequenceEntryPoint(entryPoint)
        let diff = SequenceDiagramDiff(
            old: old.sequenceDiagram(entryPoint: entry, maxDepth: maxDepth),
            new: new.sequenceDiagram(entryPoint: entry, maxDepth: maxDepth))
        let ordered = diff.union.messages.sorted { $0.order < $1.order }
        let colorByID = Dictionary(uniqueKeysWithValues: ordered.enumerated().compactMap { index, message in
            diff.status(of: message).deltaColor.map { (index, $0) }
        })
        let messageColor: @Sendable (SequenceLayoutModel.MessageLayout) -> Color? = { colorByID[$0.id] }
        let renderScale = CGFloat(scale)
        let renderPalette = palette
        return try await MainActor.run {
            try DiagramImageRenderer.renderPNG(
                sequenceDiagram: diff.union, scale: renderScale, palette: renderPalette, messageColor: messageColor)
        }
    }

    /// Renders the state-diagram delta of two revisions to PNG: the union machine with each
    /// transition tinted by its diff status. Transitions are coloured by their layout id, which
    /// equals the transition's index in the union — so parallel transitions between the same state
    /// pair on different events (which share `from`/`to` but differ in diff status) stay distinct.
    func renderStateDelta(old: CodeArtifact, new: CodeArtifact, variable: String) async throws -> Data {
        let configuration = try StateVariableSpec.configuration(from: variable, maxStates: maxStates)
        let diff = StateDiagramDiff(
            old: try old.resolvingExtensions().stateDiagram(configuration: configuration),
            new: try new.resolvingExtensions().stateDiagram(configuration: configuration))
        let transitions = diff.union.transitions
        let colorByID = Dictionary(uniqueKeysWithValues: transitions.enumerated().compactMap { index, transition in
            diff.status(of: transition).deltaColor.map { (index, $0) }
        })
        let edgeColor: @Sendable (StateLayoutModel.EdgeLayout) -> Color? = { colorByID[$0.id] }
        let renderScale = CGFloat(scale)
        let renderPalette = palette
        return try await MainActor.run {
            try DiagramImageRenderer.renderPNG(
                stateDiagram: diff.union, scale: renderScale, palette: renderPalette, edgeColor: edgeColor)
        }
    }
}

extension DeltaStatus {
    /// The delta tint for image rendering (added green / removed red / changed amber), or `nil`
    /// for `.unchanged` so the element keeps its themed colour.
    var deltaColor: Color? {
        deltaHex.map(Color.init(hex:))
    }
}

extension ClassDiagramConfiguration.Grouping: ExpressibleByArgument {}
#endif
