import AcaiCore

// Per-diagram-kind value types that each build one diagram model and pair its DOT + Mermaid renderers
// into a `DiagramExport`. Shared by every text front end (the CLI `diagram` command, the MCP
// `acai_diagram` tool) so the builder→renderer wiring lives once.

public struct ClassDiagramTextExporter: Sendable {
    public let options: ClassDiagramOptions

    public init(options: ClassDiagramOptions) {
        self.options = options
    }

    public func export(from artifact: CodeArtifact) -> DiagramExport {
        let options = options
        let diagram = ClassDiagramBuilder(options: options).build(from: artifact)
        return DiagramExport(
            dot: { ClassDiagramDOTRenderer(options: options).generate(from: diagram) },
            mermaid: { ClassDiagramMermaidRenderer(options: options).generate(from: diagram) }
        )
    }
}

public struct SequenceDiagramTextExporter: Sendable {
    public let request: SequenceDiagramRequest
    public let theme: DiagramTheme?

    public init(request: SequenceDiagramRequest, theme: DiagramTheme?) {
        self.request = request
        self.theme = theme
    }

    public func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let diagram = try request.buildTraceable(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { SequenceDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { SequenceDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

public struct StateDiagramTextExporter: Sendable {
    public let request: StateDiagramRequest
    public let theme: DiagramTheme?

    public init(request: StateDiagramRequest, theme: DiagramTheme?) {
        self.request = request
        self.theme = theme
    }

    public func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let diagram = try request.build(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { StateDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { StateDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

/// The caller injects the artifact's `LanguageConfigurationResolver` (the package build enriches
/// first, per type).
public struct PackageDiagramTextExporter: Sendable {
    public let languages: LanguageConfigurationResolver
    public let theme: DiagramTheme?

    public init(languages: LanguageConfigurationResolver, theme: DiagramTheme?) {
        self.languages = languages
        self.theme = theme
    }

    public func export(from artifact: CodeArtifact) -> DiagramExport {
        let diagram = PackageDiagramRequest().build(from: artifact, languages: languages)
        let theme = theme
        return DiagramExport(
            dot: { PackageDiagramDOTRenderer(theme: theme).render(diagram) },
            mermaid: { PackageDiagramMermaidRenderer(theme: theme).render(diagram) }
        )
    }
}

/// Emits no coverage note — a caller that wants it reads `graph.coverage` off the built graph.
public struct CallGraphTextExporter: Sendable {
    public let request: CallGraphRequest
    public let theme: DiagramTheme?

    public init(request: CallGraphRequest, theme: DiagramTheme?) {
        self.request = request
        self.theme = theme
    }

    public func export(from artifact: CodeArtifact) throws -> DiagramExport {
        let graph = try request.buildWithEdges(from: artifact)
        let theme = theme
        return DiagramExport(
            dot: { CallGraphDOTRenderer(theme: theme).render(graph) },
            mermaid: { CallGraphMermaidRenderer(theme: theme).render(graph) }
        )
    }
}
