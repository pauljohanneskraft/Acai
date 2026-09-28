#if os(macOS)
import AcaiCore
import AcaiDiagram
import Foundation

/// The diagram section for a caller with no saved diagrams; a diagram that fails becomes a `.failed` page.
public struct AtlasDiagramSet: Sendable {
    public let scale: Double
    public let palette: DiagramPalette
    public let languages: LanguageConfigurationResolver
    /// `nil` means unlimited.
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
