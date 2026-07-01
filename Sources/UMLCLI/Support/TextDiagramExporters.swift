import ArgumentParser
import Foundation
import UMLDiagram
import UMLLibrary

// Per-diagram-kind value types that each build one diagram model and pair its DOT + Mermaid
// renderers into a `DiagramExport`. Extracted from `UMLCommand.Diagram` so the command delegates
// to small, single-responsibility exporters instead of referencing every builder/renderer directly
// (which made it a fan-out outlier). `UMLCommand.Diff`/`UMLCommand.Image` reuse the shared model
// requests (see `SequenceDiagramRequest`/`CallGraphRequest`) rather than these text exporters.

/// Builds the class diagram and pairs both text renderers.
struct ClassDiagramTextExporter {
    let options: ClassDiagramOptions

    func export(from artifact: CodeArtifact) -> DiagramExport {
        let options = options
        let diagram = ClassDiagramBuilder(options: options).build(from: artifact)
        return DiagramExport(
            dot: { ClassDiagramDOTRenderer(options: options).generate(from: diagram) },
            mermaid: { ClassDiagramMermaidRenderer(options: options).generate(from: diagram) }
        )
    }
}

/// Traces a sequence diagram from the entry point and pairs both text renderers.
struct SequenceDiagramTextExporter {
    let request: SequenceDiagramRequest
    let theme: DiagramTheme?

    func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let diagram = try request.buildTraceable(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { SequenceDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { SequenceDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

/// Runs the value-flow state analysis and pairs both text renderers.
struct StateDiagramTextExporter {
    let request: StateDiagramRequest
    let theme: DiagramTheme?

    func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let diagram = try request.build(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { StateDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { StateDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

/// Builds the package/module dependency diagram and pairs both text renderers.
struct PackageDiagramTextExporter {
    let theme: DiagramTheme?

    func export(from artifact: CodeArtifact) -> DiagramExport {
        let diagram = PackageDiagramRequest().build(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { PackageDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { PackageDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

/// Builds a static call graph (optionally scoped) and pairs both text renderers. Emits the
/// resolution-coverage note to stderr, matching the original command behaviour.
struct CallGraphTextExporter {
    let request: CallGraphRequest
    let theme: DiagramTheme?

    func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let graph = try request.buildWithEdges(from: artifact)
        let percent = Int((graph.coverage.fraction * 100).rounded())
        let coverageNote = "Call graph: resolved \(graph.coverage.resolved)/\(graph.coverage.total) "
            + "call sites (\(percent)% coverage).\n"
        FileHandle.standardError.write(Data(coverageNote.utf8))
        let theme = theme
        return DiagramExport(
            dot: { CallGraphDOTRenderer(theme: theme).render(graph) },
            mermaid: { CallGraphMermaidRenderer(theme: theme).render(graph) }
        )
    }
}
