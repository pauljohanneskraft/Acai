import UMLCore

extension CodeArtifact.SourceLanguage {
    public static let cSharp = CodeArtifact.SourceLanguage(rawValue: "cSharp")
}

extension CSharpCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "void", "object", "string", "bool", "byte", "sbyte", "char", "decimal",
                "double", "float", "int", "uint", "nint", "nuint", "long", "ulong", "short", "ushort",
                "dynamic", "var"
            ],
            collectionTypeNames: [
                "Array", "List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList",
                "IEnumerable", "ICollection", "IList", "IDictionary", "IReadOnlyList",
                "IReadOnlyCollection", "IReadOnlyDictionary", "ISet"
            ],
            excludedDirectories: ["bin", "obj", ".vs"]
        )
    }
}
