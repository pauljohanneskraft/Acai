#if os(macOS)
import Foundation
import MCP
import AcaiLibrary
import AcaiRender

/// `acai_atlas` — writes the Codebase Atlas PDF and returns its path. macOS-only: the embedded
/// diagrams render through SwiftUI's `ImageRenderer`. Mirrors `acai atlas`.
struct AtlasTool: AnalysisTool {
    let name = "acai_atlas"
    let description = """
        Bundle everything about a codebase into one PDF you can hand to a person: a page per diagram \
        (class, package, call graph), the statistics, and every quality violation, dead-code \
        candidate and parse diagnostic. Use when someone wants the whole picture as a document \
        rather than one answer. Writes the file to 'output' and returns its path. macOS only.
        """

    var inputSchema: Value {
        objectSchema(
            extraProperties: rulesProperty.merging([
                "output": ["type": "string", "description": "Path to write the PDF to."],
                "name": [
                    "type": "string",
                    "description": "Name for the title page (default: the analyzed directory's name)."
                ],
                "scale": ["type": "number", "description": "Diagram resolution scale factor (default 2)."],
                "theme": ["type": "string", "enum": ["light", "dark"], "description": "Colour theme (default light)."],
                "maxNodes": [
                    "type": "integer",
                    "description": "Max node count before a graph diagram's page reports it could not render."
                ]
            ]) { _, new in new },
            required: ["path", "output"])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let output = try arguments.requiredString("output")
        let languages = artifact.standardLanguageResolver

        let analysis = AtlasAnalysis(
            artifact: artifact, rules: try qualityRules(arguments), languages: languages)
        let diagrams = await AtlasDiagramSet(
            scale: try arguments.double("scale") ?? 2,
            palette: arguments.string("theme") == "dark" ? .dark : .light,
            languages: languages,
            maxNodes: try arguments.int("maxNodes") ?? DiagramNodeLimit.defaultMaximum
        ).pages(for: artifact)

        let document = AtlasDocument(
            codebaseName: try codebaseName(arguments), diagrams: diagrams,
            metrics: analysis.metrics, findings: analysis.findings)
        let data = try document.pdfData()
        do {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } catch {
            throw MCPError.invalidParams("Could not write the atlas to \(output): \(error.localizedDescription)")
        }
        return .json(try Value(Payload(
            path: output, formatVersion: AtlasDocument.formatVersion,
            diagramCount: diagrams.count, findingCount: analysis.findings.count, byteCount: data.count)))
    }

    private struct Payload: Codable {
        var path: String
        var formatVersion: Int
        var diagramCount: Int
        var findingCount: Int
        var byteCount: Int
    }

    private func codebaseName(_ arguments: ToolArguments) throws -> String {
        if let name = arguments.string("name") { return name }
        let path = try arguments.requiredString("path")
        return URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
    }
}
#endif
