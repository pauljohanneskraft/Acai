import UMLCore

// UMLConformanceTests builds small artifacts by hand and enriches them with a representative
// classification, mirroring UMLCoreTests' fixture. Production always injects a real language
// configuration; tests opt into this one explicitly.
extension CodeArtifact.SourceLanguage {
    static let swift = CodeArtifact.SourceLanguage(rawValue: "swift")
}

extension LanguageConfiguration {
    static let test = LanguageConfiguration(
        primitiveTypeNames: ["Void", "String", "Int", "Double", "Bool", "Optional"],
        collectionTypeNames: ["Array", "Set", "Dictionary", "List", "Map"],
        annotationStereotypes: ["entity": "entity", "repository": "repository"]
    )
}

extension CodeArtifact {
    func enriched() -> CodeArtifact { enriched(configuration: .test) }
}
