#if os(macOS)
import CoreGraphics
import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLDiff

// Per-diagram-kind PNG rendering shared by the CLI `uml image` command and the MCP `uml_image` tool.
// Each value carries the output scale + palette and renders one diagram kind — plain and, where it has
// a two-revision form, a delta with each element tinted by its diff status — via the UMLRender
// `*ImageRenderer`s. Promoted here from the CLI. Kinds that enrich (class, package) take the artifact's
// `LanguageConfiguration` injected, so this target names no language.

/// Class-diagram PNG rendering.
public struct ClassImageExporter: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let configuration: ClassDiagramConfiguration
    public let languages: LanguageConfigurationResolver

    public init(
        scale: Double, palette: DiagramPalette,
        configuration: ClassDiagramConfiguration, languages: LanguageConfigurationResolver
    ) {
        self.scale = scale
        self.palette = palette
        self.configuration = configuration
        self.languages = languages
    }

    public func render(artifact: CodeArtifact) async throws -> Data {
        let (configuration, scale, palette, languages) = (configuration, scale, palette, languages)
        return try await MainActor.run {
            try ClassImageRenderer().renderPNG(
                artifact: artifact, configuration: configuration, languages: languages,
                context: RenderingContext(scale: CGFloat(scale), palette: palette))
        }
    }

    /// The union diagram with each edge/node tinted by its diff status (added green / removed red /
    /// changed amber).
    public func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let differ = ArtifactDiffer()
        let diff = differ.diff(old: old, new: new)
        let union = differ.unionArtifact(old: old, new: new)
        let edgeStatus = diff.relationshipStatusLookup()
        let typeStatus = diff.typeStatusLookup()
        let edgeColor: @Sendable (GeneratedDiagramEdge) -> Color? = { edge in
            edgeStatus(Relationship(kind: edge.kind, source: edge.sourceID, target: edge.targetID)).deltaColor
        }
        let nodeColor: @Sendable (GeneratedDiagramNode) -> Color? = { typeStatus($0.id).deltaColor }
        let (configuration, scale, palette, languages) = (configuration, scale, palette, languages)
        return try await MainActor.run {
            try ClassImageRenderer().renderPNG(
                artifact: union, configuration: configuration, languages: languages,
                context: RenderingContext(scale: CGFloat(scale), palette: palette),
                colors: ClassColorOverrides(edge: edgeColor, node: nodeColor))
        }
    }
}

/// Sequence-diagram PNG rendering traced from an entry point.
public struct SequenceImageExporter: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let entryPoint: String
    public let maxDepth: Int
    /// Mapping entries, applied to the plain trace only (the delta path traces both sides unmapped,
    /// preserving the original behaviour).
    public let map: [String]

    public init(
        scale: Double, palette: DiagramPalette, entryPoint: String, maxDepth: Int, map: [String] = []
    ) {
        self.scale = scale
        self.palette = palette
        self.entryPoint = entryPoint
        self.maxDepth = maxDepth
        self.map = map
    }

    public func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = try SequenceDiagramRequest(entryPoint: entryPoint, maxDepth: maxDepth, map: map)
            .buildTraceable(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try SequenceImageRenderer().renderPNG(
                sequenceDiagram: diagram, context: RenderingContext(scale: CGFloat(scale), palette: palette))
        }
    }

    /// The union trace with each message tinted by its diff status. Messages are coloured by their
    /// layout id, which equals the message's position in the (order-sorted) union.
    public func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = SequenceDiagramRequest(entryPoint: entryPoint, maxDepth: maxDepth)
        let diff = SequenceDiagramDiff(old: try request.build(from: old), new: try request.build(from: new))
        let ordered = diff.union.messages.sorted { $0.order < $1.order }
        let colorByID = Dictionary(uniqueKeysWithValues: ordered.enumerated().compactMap { index, message in
            diff.status(of: message).deltaColor.map { (index, $0) }
        })
        let messageColor: @Sendable (SequenceLayoutModel.MessageLayout) -> Color? = { colorByID[$0.id] }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try SequenceImageRenderer().renderPNG(
                sequenceDiagram: diff.union, context: RenderingContext(scale: CGFloat(scale), palette: palette),
                messageColor: messageColor)
        }
    }
}

/// Value-flow state-diagram PNG rendering for a variable.
public struct StateImageExporter: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let variable: String
    public let maxStates: Int

    public init(scale: Double, palette: DiagramPalette, variable: String, maxStates: Int) {
        self.scale = scale
        self.palette = palette
        self.variable = variable
        self.maxStates = maxStates
    }

    private var request: StateDiagramRequest { StateDiagramRequest(variable: variable, maxStates: maxStates) }

    public func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = try request.build(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try StateImageRenderer().renderPNG(
                stateDiagram: diagram, context: RenderingContext(scale: CGFloat(scale), palette: palette))
        }
    }

    /// The union machine with each transition tinted by its diff status. Transitions are coloured by
    /// their layout id (their index in the union), so parallel transitions on different events stay
    /// distinct.
    public func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = request
        let diff = StateDiagramDiff(old: try request.build(from: old), new: try request.build(from: new))
        let transitions = diff.union.transitions
        let colorByID = Dictionary(uniqueKeysWithValues: transitions.enumerated().compactMap { index, transition in
            diff.status(of: transition).deltaColor.map { (index, $0) }
        })
        let edgeColor: @Sendable (StateLayoutModel.EdgeLayout) -> Color? = { colorByID[$0.id] }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try StateImageRenderer().renderPNG(
                stateDiagram: diff.union, context: RenderingContext(scale: CGFloat(scale), palette: palette),
                edgeColor: edgeColor)
        }
    }
}

/// Package/module dependency-diagram PNG rendering. Takes the artifact's `LanguageConfiguration`
/// injected (the package build enriches first).
public struct PackageImageExporter: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let languages: LanguageConfigurationResolver

    public init(scale: Double, palette: DiagramPalette, languages: LanguageConfigurationResolver) {
        self.scale = scale
        self.palette = palette
        self.languages = languages
    }

    public func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = PackageDiagramRequest().build(from: artifact, languages: languages)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try PackageImageRenderer().renderPNG(
                packageDiagram: diagram, context: RenderingContext(scale: CGFloat(scale), palette: palette))
        }
    }

    /// The union with each module node and dependency edge tinted by its diff status.
    public func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = PackageDiagramRequest()
        let languages = languages
        let diff = PackageDiagramDiff(
            old: request.build(from: old, languages: languages),
            new: request.build(from: new, languages: languages))
        let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
        let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try PackageImageRenderer().renderPNG(
                packageDiagram: diff.union, context: RenderingContext(scale: CGFloat(scale), palette: palette),
                colors: GraphColorOverrides(node: nodeColor, edge: edgeColor))
        }
    }
}

/// Static call-graph PNG rendering for an optional scope.
public struct CallGraphImageExporter: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let scope: CallGraphScopeOption

    public init(scale: Double, palette: DiagramPalette, scope: CallGraphScopeOption) {
        self.scale = scale
        self.palette = palette
        self.scope = scope
    }

    public func render(artifact: CodeArtifact) async throws -> Data {
        let graph = try CallGraphRequest(scope: scope).buildWithEdges(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try CallGraphImageRenderer().renderPNG(
                callGraph: graph, context: RenderingContext(scale: CGFloat(scale), palette: palette))
        }
    }

    /// The union with each method node and call edge tinted by its diff status.
    public func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = CallGraphRequest(scope: scope)
        let diff = CallGraphDiff(old: try request.build(from: old), new: try request.build(from: new))
        let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
        let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try CallGraphImageRenderer().renderPNG(
                callGraph: diff.union, context: RenderingContext(scale: CGFloat(scale), palette: palette),
                colors: GraphColorOverrides(node: nodeColor, edge: edgeColor))
        }
    }
}

extension DeltaStatus {
    /// The delta tint for image rendering (added green / removed red / changed amber), or `nil` for
    /// `.unchanged` so the element keeps its themed colour.
    var deltaColor: Color? {
        deltaHex.map(Color.init(hex:))
    }
}
#endif
