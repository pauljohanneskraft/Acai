import UMLCore

extension CodeArtifact.SourceLanguage {
    public static let ruby = CodeArtifact.SourceLanguage(rawValue: "ruby")
}

extension RubyCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "Integer", "Float", "Complex", "Rational", "String", "Symbol",
                "TrueClass", "FalseClass", "NilClass", "Object", "BasicObject", "Numeric"
            ],
            collectionTypeNames: [
                "Array", "Hash", "Set", "Range", "Enumerable"
            ],
            excludedDirectories: [
                ".bundle", "vendor", "tmp", "log", ".git"
            ]
        )
    }
}
