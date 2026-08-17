import CoreGraphics
import Foundation
import AcaiCore
import AcaiLibrary
@testable import AcaiRender

// AcaiRender's layout/render model takes the source language's configuration explicitly. These
// test conveniences resolve it from the standard registry (the same one production uses), so
// render tests don't repeat the lookup; production keeps the parameter required and explicit.

extension DiagramLayoutModel {
    init(artifact: CodeArtifact, configuration: ClassDiagramConfiguration) {
        self.init(
            artifact: artifact,
            configuration: configuration,
            languages: artifact.standardLanguageResolver
        )
    }
}

extension ClassImageRenderer {
    func renderPNG(
        artifact: CodeArtifact,
        configuration: ClassDiagramConfiguration,
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light
    ) throws -> Data {
        try renderPNG(
            artifact: artifact,
            configuration: configuration,
            languages: artifact.standardLanguageResolver,
            context: RenderingContext(scale: scale, padding: padding, palette: palette)
        )
    }
}
