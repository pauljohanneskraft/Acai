import UMLCore

// Per-diagram-kind value types that each build one diagram model and pair its DOT + Mermaid renderers
// into a `DiagramExport`. Shared by every text front end (the CLI `diagram` command, the MCP
// `uml_diagram` tool) so the builder→renderer wiring lives once. Promoted here from the CLI.

/// Builds the class diagram and pairs both text renderers.
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

/// Traces a sequence diagram from the entry point and pairs both text renderers.
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

/// Runs the value-flow state analysis and pairs both text renderers.
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

/// Builds the package/module dependency diagram and pairs both text renderers. The caller injects the
/// artifact's `LanguageConfigurationResolver` (the package build enriches first, per type).
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

/// Builds a static call graph (optionally scoped) and pairs both text renderers. Unlike the CLI's
/// former copy it emits no coverage note — a caller that wants it reads `graph.coverage` off the
/// built graph.
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
