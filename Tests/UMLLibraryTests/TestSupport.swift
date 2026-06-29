import UMLCore
import UMLDiagram
import UMLLibrary

extension ClassDiagramDOTRenderer {
    /// Test convenience: a generator whose options carry `artifact`'s standard language
    /// configuration, resolved from the composition root just as production does.
    init(for artifact: CodeArtifact) {
        self.init(options: ClassDiagramOptions(language: artifact.standardLanguageConfiguration))
    }
}
