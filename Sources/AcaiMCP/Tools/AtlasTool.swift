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
        (the default class diagram, package graph and call graph), the statistics, and every quality \
        violation, dead-code candidate and parse diagnostic. Same document format as the app's Codebase \
        Atlas export. Use when someone wants the whole picture as a document rather than one answer. \
        Writes the file to 'output' and returns its absolute path. macOS only.
        """

    let isReadOnly = false

    var inputSchema: Value {
        objectSchema(
            extraProperties: rulesProperty.merging([
                "output": ["type": "string", "description": "Path to write the PDF to."],
                "name": [
                    "type": "string",
                    "description": "Name for the title page (default: the analyzed directory's name)."
                ],
                "scale": [
                    "type": "number",
                    "description": "Diagram resolution scale factor, greater than 0 (default 2)."
                ],
                "theme": ["type": "string", "enum": ["light", "dark"], "description": "Colour theme (default light)."],
                "maxNodes": [
                    "type": "integer",
                    "description": .string(maxNodesDescription)
                ]
            ]) { _, new in new },
            required: ["path", "output"])
    }

    private var maxNodesDescription: String {
        let allowed = DiagramNodeLimit.allowedMaximums
        return "Max node count before a graph diagram's page reports it could not render "
            + "(\(allowed.lowerBound)–\(allowed.upperBound), default \(DiagramNodeLimit.defaultMaximum))."
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let output = URL(fileURLWithPath: try arguments.requiredString("output")).standardizedFileURL
        let scale = try arguments.double("scale") ?? 2
        guard scale > 0 else {
            throw MCPError.invalidParams("scale must be greater than 0.")
        }
        let maxNodes = try arguments.int("maxNodes") ?? DiagramNodeLimit.defaultMaximum
        let allowed = DiagramNodeLimit.allowedMaximums
        guard allowed.contains(maxNodes) else {
            throw MCPError.invalidParams(
                "maxNodes must be between \(allowed.lowerBound) and \(allowed.upperBound).")
        }
        let rules = try qualityRules(arguments)
        let artifact = try await resolveArtifact(arguments, cache)
        let languages = artifact.standardLanguageResolver

        let analysis = AtlasAnalysis(artifact: artifact, rules: rules, languages: languages)
        let diagrams = await AtlasDiagramSet(
            scale: scale,
            palette: arguments.string("theme") == "dark" ? .dark : .light,
            languages: languages,
            maxNodes: maxNodes
        ).pages(for: artifact)

        let document = AtlasDocument(
            codebaseName: try codebaseName(arguments), diagrams: diagrams,
            metrics: analysis.metrics, findings: analysis.findings)
        let data = try document.pdfData()
        do {
            try data.write(to: output, options: .atomic)
        } catch {
            throw MCPError.invalidParams("Could not write the atlas to \(output.path): \(error.localizedDescription)")
        }
        return .json(try Value(Payload(
            path: output.path, formatVersion: AtlasDocument.formatVersion,
            diagramCount: diagrams.count, findingCount: analysis.findings.count, byteCount: data.count,
            unrenderedDiagrams: diagrams.compactMap { page in
                page.image.failureReason.map { "\(page.name): \($0)" }
            })))
    }

    private struct Payload: Codable {
        var path: String
        var formatVersion: Int
        var diagramCount: Int
        var findingCount: Int
        var byteCount: Int
        var unrenderedDiagrams: [String]
    }

    private func codebaseName(_ arguments: ToolArguments) throws -> String {
        if let name = arguments.string("name") { return name }
        let path = try arguments.requiredString("path")
        return URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
    }
}
#endif
