import AcaiCore
import AcaiRender
import Foundation

/// The app's side of the Codebase Atlas: renders each of the codebase's generated diagrams through
/// the on-canvas view models (so the user's saved node positions are the ones exported) and hands
/// them, the metrics and the findings to the shared `AtlasDocument`, which owns the bundling for
/// the app, `acai atlas` and `acai_atlas` alike.
///
/// `@MainActor` because diagram PNG rendering goes through `ImageRenderer`, which requires it —
/// this also makes the struct implicitly `Sendable` despite `Codebase` not being `Sendable`
/// itself, so it can be captured by `ActivityCenter.run`'s `@Sendable` closure.
@MainActor
struct CodebaseAtlasExport {
    let codebase: Codebase
    let artifact: CodeArtifact
    let diagrams: [GeneratedDiagram]
    let analysis: CodebaseAnalysis

    func build() async throws -> Data {
        let renderer = CodebaseAtlasDiagramRenderer(codebase: codebase, artifact: artifact)
        var pages: [AtlasDiagramPage] = []
        for diagram in diagrams {
            try Task.checkCancellation()
            pages.append(AtlasDiagramPage(
                name: diagram.name, subtitle: diagram.type.displayName,
                image: renderer.render(diagram, scale: AtlasDocument.renderScale).atlasImage))
            await Task.yield()
        }
        try Task.checkCancellation()
        let document = AtlasDocument(
            codebaseName: codebase.name, diagrams: pages, metrics: analysis.metrics,
            findings: AtlasFindings(
                quality: analysis.quality, deadCode: analysis.deadCode, health: analysis.health).findings)
        // Laying out and writing the PDF needs no main actor, and grows with the codebase.
        return try await Task.detached { try document.pdfData() }.value
    }
}

extension AtlasDiagramRenderOutcome {
    var atlasImage: AtlasDiagramPage.Image {
        switch self {
        case .rendered(let data):
            .rendered(data)
        case .unsupported:
            .unsupported
        case .failed:
            .failed
        }
    }
}
