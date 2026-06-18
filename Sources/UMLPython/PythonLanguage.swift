import UMLCore

// The Python language's identity and quirks. Python has no single dominant code generator, so no
// generated-code filter is configured (mirroring the Java/Kotlin/JS plugins).

extension CodeArtifact.SourceLanguage {
    public static let python = CodeArtifact.SourceLanguage(rawValue: "python")
}

extension PythonCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "int", "float", "complex", "bool", "str", "bytes", "bytearray",
                "None", "NoneType", "object", "Any", "type"
            ],
            collectionTypeNames: [
                // builtins (PEP 585) + their typing-module capitalized aliases
                "list", "dict", "set", "frozenset", "tuple",
                "List", "Dict", "Set", "FrozenSet", "Tuple",
                "Sequence", "Mapping", "MutableMapping", "Iterable", "Iterator", "Collection"
            ],
            annotationStereotypes: [
                "dataclass": "dataclass"
            ],
            generatedCodeFilter: nil,
            excludedDirectories: [
                "__pycache__", ".venv", "venv", "env", ".tox", ".mypy_cache",
                ".pytest_cache", ".eggs", "build", "dist", "site-packages", ".git"
            ]
        )
    }
}
