import AcaiCore

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
            generatedCodeFilter: nil,  // no single dominant Python code generator to filter
            excludedDirectories: [
                "__pycache__", ".venv", "venv", "env", ".tox", ".mypy_cache",
                ".pytest_cache", ".eggs", "build", "dist", "site-packages", ".git"
            ],
            // pytest fixtures and dunder hooks are invoked by the runtime/test framework, not by
            // resolvable call sites.
            entryPointMarkers: EntryPointMarkers(
                annotations: ["fixture", "pytestfixture"],
                // pytest and unittest find their hooks by name, not by conformance, so these stay
                // name-based. `__init__` is not among them: construction already targets it, so a
                // genuinely unconstructed type's initializer is a real finding.
                methodNames: ["main", "setup_method", "teardown_method", "setup", "teardown"]),
            // A bare `Thing()` now resolves through `CallSiteScope.bareCall`'s constructor opt-in to
            // a call-site edge targeting the initializer's fixed `__init__` member. `__getitem__` is
            // extracted as a method and is scanned as one.
            deadCodeMemberKinds: [.method, .initializer]
        )
    }
}
