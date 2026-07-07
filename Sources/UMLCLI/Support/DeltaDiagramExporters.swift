import ArgumentParser
import Foundation
import UMLDiagram
import UMLDiff
import UMLLibrary

// Per-diagram-kind delta text rendering for `uml diff --diagram`. Each type builds the diagram model
// from both revisions (via the shared requests), diffs the two models, and renders the union with
// added=green/removed=red/changed=amber colour overrides. Extracted from `UMLCommand.Diff` so the
// command delegates to small exporters instead of referencing every diff type and renderer directly.

/// Class-diagram delta: the union artifact with each type/edge tinted by its diff status.
struct ClassDeltaExporter {
    func render(old: CodeArtifact, new: CodeArtifact, format: DiagramFormat) -> String {
        let differ = ArtifactDiffer()
        let diff = differ.diff(old: old, new: new)
        let edgeStatus = diff.relationshipStatusLookup()
        let typeStatus = diff.typeStatusLookup()
        let options = ClassDiagramOptions(
            showExternalTypes: true,
            languages: new.standardLanguageResolver,
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
}

/// Sequence-diagram delta traced from an entry point.
struct SequenceDeltaExporter {
    let request: SequenceDiagramRequest

    func render(old: CodeArtifact, new: CodeArtifact, format: DiagramFormat) throws -> String {
        let diff = SequenceDiagramDiff(old: try request.build(from: old), new: try request.build(from: new))
        switch format {
        case .dot:
            return SequenceDiagramDOTRenderer(messageColor: { diff.status(of: $0).deltaHex }).render(diff.union)
        case .mermaid:
            // Mermaid sequence syntax has no per-message colour; render the union uncolored.
            return SequenceDiagramMermaidRenderer().render(diff.union)
        }
    }
}

/// Value-flow state-diagram delta for a variable.
struct StateDeltaExporter {
    let request: StateDiagramRequest

    func render(old: CodeArtifact, new: CodeArtifact, format: DiagramFormat) throws -> String {
        let diff = StateDiagramDiff(old: try request.build(from: old), new: try request.build(from: new))
        switch format {
        case .dot:
            return StateDiagramDOTRenderer(transitionColor: { diff.status(of: $0).deltaHex }).render(diff.union)
        case .mermaid:
            // Mermaid state syntax has no per-transition colour; render the union uncolored.
            return StateDiagramMermaidRenderer().render(diff.union)
        }
    }
}

/// Package/module dependency-diagram delta.
struct PackageDeltaExporter {
    func render(old: CodeArtifact, new: CodeArtifact, format: DiagramFormat) -> String {
        let request = PackageDiagramRequest()
        let diff = PackageDiagramDiff(
            old: request.build(from: old, languages: old.standardLanguageResolver),
            new: request.build(from: new, languages: new.standardLanguageResolver))
        let nodeColor: @Sendable (String) -> String? = { diff.status(ofNode: $0).deltaHex }
        let edgeColor: @Sendable (String, String) -> String? = { diff.status(ofEdgeFrom: $0, to: $1).deltaHex }
        switch format {
        case .dot:
            return PackageDiagramDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
        case .mermaid:
            return PackageDiagramMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
        }
    }
}

/// Static call-graph delta.
struct CallGraphDeltaExporter {
    let request: CallGraphRequest

    func render(old: CodeArtifact, new: CodeArtifact, format: DiagramFormat) throws -> String {
        let diff = CallGraphDiff(old: try request.build(from: old), new: try request.build(from: new))
        let nodeColor: @Sendable (String) -> String? = { diff.status(ofNode: $0).deltaHex }
        let edgeColor: @Sendable (String, String) -> String? = { diff.status(ofEdgeFrom: $0, to: $1).deltaHex }
        switch format {
        case .dot:
            return CallGraphDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
        case .mermaid:
            return CallGraphMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
        }
    }
}
