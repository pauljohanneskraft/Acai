import CoreGraphics
import Foundation
import UMLCore
import UMLLibrary
@testable import UMLRender

// UMLRender's layout/render model now takes the source language's configuration explicitly. These
// test conveniences restore the former signatures by resolving that configuration from the standard
// registry (the same source production uses), so render tests don't repeat the lookup. Production
// keeps the configuration a required, explicit parameter.

extension DiagramLayoutModel {
    init(artifact: CodeArtifact, configuration: ClassDiagramConfiguration) {
        self.init(
            artifact: artifact,
            configuration: configuration,
            language: artifact.standardLanguageConfiguration
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
            language: artifact.standardLanguageConfiguration,
            context: RenderingContext(scale: scale, padding: padding, palette: palette)
        )
    }
}
