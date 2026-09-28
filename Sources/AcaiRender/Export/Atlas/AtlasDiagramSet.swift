#if os(macOS)
import AcaiCore
import AcaiDiagram
import Foundation

/// The Atlas's diagram section for a caller with no saved diagrams of its own: the three kinds that
/// need no per-diagram configuration — the whole-codebase class diagram, the module/package graph
/// and the call graph. The kinds that need an entry point (sequence) or a variable (state) are left
/// out rather than guessed at.
///
/// A value you instantiate over the output settings and ask for `pages(for:)`. A kind that fails to
/// render (a node limit, a renderer error) becomes a `.failed` page rather than failing the whole
/// Atlas, so the document's shape never depends on one diagram's luck.
public struct AtlasDiagramSet: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let languages: LanguageConfigurationResolver
    /// Rendering a graph diagram fails once it would exceed this many nodes. `nil` means unlimited.
    public let maxNodes: Int?

    public init(
        scale: Double, palette: DiagramPalette, languages: LanguageConfigurationResolver, maxNodes: Int? = nil
    ) {
        self.scale = scale
        self.palette = palette
        self.languages = languages
        self.maxNodes = maxNodes
    }

    public func pages(for artifact: CodeArtifact) async -> [AtlasDiagramPage] {
        var configuration = ClassDiagramConfiguration()
        configuration.maxNodes = maxNodes
        return [
            await page(named: "Class Diagram", subtitle: "Whole codebase") {
                try await ClassImageExporter(
                    scale: scale, palette: palette, configuration: configuration, languages: languages
                ).render(artifact: artifact)
            },
            await page(named: "Package Diagram", subtitle: "Module dependencies") {
                try await PackageImageExporter(
                    scale: scale, palette: palette, languages: languages, maxNodes: maxNodes
                ).render(artifact: artifact)
            },
            await page(named: "Call Graph", subtitle: "Whole codebase") {
                try await CallGraphImageExporter(
                    scale: scale, palette: palette, scope: CallGraphScopeOption(raw: nil)
                ).render(artifact: artifact)
            }
        ]
    }

    private func page(
        named name: String, subtitle: String, render: () async throws -> Data
    ) async -> AtlasDiagramPage {
        do {
            return AtlasDiagramPage(name: name, subtitle: subtitle, image: .rendered(try await render()))
        } catch {
            return AtlasDiagramPage(name: name, subtitle: subtitle, image: .init(failure: error))
        }
    }
}
#endif
