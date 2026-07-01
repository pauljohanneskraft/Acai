#if os(macOS)
import CoreGraphics
import Foundation
import SwiftUI
import UMLDiagram
import UMLDiff
import UMLLibrary
import UMLRender

// Per-diagram-kind PNG rendering for `uml image`. Each value carries the output scale + palette and
// renders one diagram kind — plain and, where it has a two-revision form, a delta with each element
// tinted by its diff status — via `DiagramImageRenderer`. Extracted from `UMLCommand.Image` so the
// command delegates instead of referencing every diff type, layout model, and the renderer directly.

/// Class-diagram PNG rendering.
struct ClassImageExporter {
    let scale: Double
    let palette: DiagramPalette
    let configuration: ClassDiagramConfiguration

    func render(artifact: CodeArtifact) async throws -> Data {
        let language = artifact.standardLanguageConfiguration
        let (configuration, scale, palette) = (configuration, scale, palette)
        return try await MainActor.run {
            try ClassImageRenderer().renderPNG(
                artifact: artifact, configuration: configuration, language: language,
                scale: CGFloat(scale), palette: palette)
        }
    }

    /// The union diagram with each edge/node tinted by its diff status (added green / removed red /
    /// changed amber).
    func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let differ = ArtifactDiffer()
        let diff = differ.diff(old: old, new: new)
        let union = differ.unionArtifact(old: old, new: new)
        let edgeStatus = diff.relationshipStatusLookup()
        let typeStatus = diff.typeStatusLookup()
        let edgeColor: @Sendable (GeneratedDiagramEdge) -> Color? = { edge in
            edgeStatus(Relationship(kind: edge.kind, source: edge.sourceID, target: edge.targetID)).deltaColor
        }
        let nodeColor: @Sendable (GeneratedDiagramNode) -> Color? = { typeStatus($0.id).deltaColor }
        let language = union.standardLanguageConfiguration
        let (configuration, scale, palette) = (configuration, scale, palette)
        return try await MainActor.run {
            try ClassImageRenderer().renderPNG(
                artifact: union, configuration: configuration, language: language,
                scale: CGFloat(scale), palette: palette, edgeColor: edgeColor, nodeColor: nodeColor)
        }
    }
}

/// Sequence-diagram PNG rendering traced from an entry point.
struct SequenceImageExporter {
    let scale: Double
    let palette: DiagramPalette
    let entryPoint: String
    let maxDepth: Int
    /// `--map` entries, applied to the plain trace only (the delta path traces both sides unmapped,
    /// preserving the original command's behaviour).
    var map: [String] = []

    func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = try SequenceDiagramRequest(entryPoint: entryPoint, maxDepth: maxDepth, map: map)
            .buildTraceable(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try SequenceImageRenderer().renderPNG(sequenceDiagram: diagram, scale: CGFloat(scale), palette: palette)
        }
    }

    /// The union trace with each message tinted by its diff status. Messages are coloured by their
    /// layout id, which equals the message's position in the (order-sorted) union.
    func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
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
                sequenceDiagram: diff.union, scale: CGFloat(scale), palette: palette, messageColor: messageColor)
        }
    }
}

/// Value-flow state-diagram PNG rendering for a variable.
struct StateImageExporter {
    let scale: Double
    let palette: DiagramPalette
    let variable: String
    let maxStates: Int

    private var request: StateDiagramRequest { StateDiagramRequest(variable: variable, maxStates: maxStates) }

    func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = try request.build(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try StateImageRenderer().renderPNG(stateDiagram: diagram, scale: CGFloat(scale), palette: palette)
        }
    }

    /// The union machine with each transition tinted by its diff status. Transitions are coloured by
    /// their layout id (their index in the union), so parallel transitions on different events stay
    /// distinct.
    func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
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
                stateDiagram: diff.union, scale: CGFloat(scale), palette: palette, edgeColor: edgeColor)
        }
    }
}

/// Package/module dependency-diagram PNG rendering.
struct PackageImageExporter {
    let scale: Double
    let palette: DiagramPalette

    func render(artifact: CodeArtifact) async throws -> Data {
        let diagram = PackageDiagramRequest().build(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try PackageImageRenderer().renderPNG(packageDiagram: diagram, scale: CGFloat(scale), palette: palette)
        }
    }

    /// The union with each module node and dependency edge tinted by its diff status.
    func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = PackageDiagramRequest()
        let diff = PackageDiagramDiff(old: request.build(from: old), new: request.build(from: new))
        let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
        let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try PackageImageRenderer().renderPNG(
                packageDiagram: diff.union, scale: CGFloat(scale), palette: palette,
                nodeColor: nodeColor, edgeColor: edgeColor)
        }
    }
}

/// Static call-graph PNG rendering for an optional scope.
struct CallGraphImageExporter {
    let scale: Double
    let palette: DiagramPalette
    let scope: CallGraphScopeOption

    func render(artifact: CodeArtifact) async throws -> Data {
        let graph = try CallGraphRequest(scope: scope).buildWithEdges(from: artifact)
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try CallGraphImageRenderer().renderPNG(callGraph: graph, scale: CGFloat(scale), palette: palette)
        }
    }

    /// The union with each method node and call edge tinted by its diff status.
    func renderDelta(old: CodeArtifact, new: CodeArtifact) async throws -> Data {
        let request = CallGraphRequest(scope: scope)
        let diff = CallGraphDiff(old: try request.build(from: old), new: try request.build(from: new))
        let nodeColor: @Sendable (String) -> Color? = { diff.status(ofNode: $0).deltaColor }
        let edgeColor: @Sendable (String, String) -> Color? = { diff.status(ofEdgeFrom: $0, to: $1).deltaColor }
        let (scale, palette) = (scale, palette)
        return try await MainActor.run {
            try CallGraphImageRenderer().renderPNG(
                callGraph: diff.union, scale: CGFloat(scale), palette: palette,
                nodeColor: nodeColor, edgeColor: edgeColor)
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
#endif
