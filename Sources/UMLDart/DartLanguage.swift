import UMLCore

// The Dart language's identity and quirks, including the code-generation filter for the
// freezed / build_runner / json_serializable ecosystem (`.freezed.dart`, `_$Foo`, …).

extension CodeArtifact.SourceLanguage {
    public static let dart = CodeArtifact.SourceLanguage(rawValue: "dart")
}

extension DartCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "void", "dynamic", "Object", "Null", "Never", "var", "inferred",
                "num", "int", "double", "bool", "String"
            ],
            collectionTypeNames: [
                "List", "Map", "Set", "Iterable"
            ],
            generatedCodeFilter: GeneratedCodeFilter(
                displayName: "Dart Generated Types",
                explanation: "Hides types from .freezed.dart, .g.dart and other code-generated files.",
                fileSuffixes: [
                    ".freezed.dart", ".g.dart", ".gr.dart",
                    ".config.dart", ".chopper.dart", ".mocks.dart", ".mapper.dart"
                ],
                typeNamePatterns: [
                    NamePattern(prefix: "_$"),               // freezed implementation classes
                    NamePattern(prefix: "$", suffix: "CopyWith")  // freezed copy-with interfaces
                ]
            ),
            excludedDirectories: [".dart_tool", "build"],
            // Flutter widget lifecycle methods are called by the framework, not by resolvable call
            // sites; `main` is the app entry point.
            entryPointMarkers: EntryPointMarkers(
                methodNames: [
                    "main", "build", "createstate", "initstate", "dispose",
                    "didchangedependencies", "didupdatewidget"
                ])
        )
    }
}
