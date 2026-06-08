public struct CodeArtifact: Codable, Equatable, Hashable, Sendable {
    public var metadata: Metadata
    public var types: [TypeDeclaration]
    public var relationships: [Relationship]
    public var freestandingFunctions: [Member]
    /// Top-level (module-scope) `let`/`var` declarations.
    public var globalVariables: [Member]

    public init(
        metadata: Metadata,
        types: [TypeDeclaration] = [],
        relationships: [Relationship] = [],
        freestandingFunctions: [Member] = [],
        globalVariables: [Member] = []
    ) {
        self.metadata = metadata
        self.types = types
        self.relationships = relationships
        self.freestandingFunctions = freestandingFunctions
        self.globalVariables = globalVariables
    }

    public struct Metadata: Codable, Equatable, Hashable, Sendable {
        public var sourceLanguage: SourceLanguage
        public var filePaths: [String]
        public var toolVersion: String?
        /// `true` when at least one source file could not be fully parsed
        /// (best-effort tree contained missing/unexpected nodes).
        public var hasParseErrors: Bool

        public init(
            sourceLanguage: SourceLanguage,
            filePaths: [String] = [],
            toolVersion: String? = nil,
            hasParseErrors: Bool = false
        ) {
            self.sourceLanguage = sourceLanguage
            self.filePaths = filePaths
            self.toolVersion = toolVersion
            self.hasParseErrors = hasParseErrors
        }
    }

    public enum SourceLanguage: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        case swift
        case kotlin
        case java
        case typeScript
        case javaScript
        case dart
    }
}

extension CodeArtifact {
    public func merging(with other: CodeArtifact) -> CodeArtifact {
        CodeArtifact(
            metadata: Metadata(
                sourceLanguage: metadata.sourceLanguage,
                filePaths: metadata.filePaths + other.metadata.filePaths,
                toolVersion: metadata.toolVersion ?? other.metadata.toolVersion,
                hasParseErrors: metadata.hasParseErrors || other.metadata.hasParseErrors
            ),
            types: types + other.types,
            relationships: relationships + other.relationships,
            freestandingFunctions: freestandingFunctions + other.freestandingFunctions,
            globalVariables: globalVariables + other.globalVariables
        )
    }

    public func resolvingExtensions() -> CodeArtifact {
        var resolvedTypes = types.filter { $0.kind != .extension }
        let extensions = types.filter { $0.kind == .extension }
        // Drop any standalone extension edges; conformances are re-derived below so
        // their source is the real target id (never a dangling `extension.*` node).
        var resolvedRelationships = relationships.filter { $0.kind != .extension }

        for ext in extensions {
            guard let targetName = ext.extensionOf,
                  let targetId = Self.mergeExtension(ext, targetName: targetName, into: &resolvedTypes)
            else {
                // Extension of an external type (e.g. `extension Array`, `extension UUID`):
                // dropped entirely — neither node nor conformance edge is kept.
                continue
            }
            for inherited in ext.inheritedTypes {
                resolvedRelationships.append(
                    Relationship(kind: .conformance, source: targetId, target: inherited.name)
                )
            }
        }

        return CodeArtifact(
            metadata: metadata,
            types: resolvedTypes,
            relationships: resolvedRelationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Generated Dart File Filtering

    /// File-name suffixes used by Dart code-generators (freezed, build_runner,
    /// json_serializable, auto_route, injectable, mockito, chopper, etc.).
    private static let generatedDartFileSuffixes: [String] = [
        ".freezed.dart",
        ".g.dart",
        ".gr.dart",
        ".config.dart",
        ".chopper.dart",
        ".mocks.dart",
        ".mapper.dart"
    ]

    /// Returns `true` when the file path looks like a Dart generated file.
    private static func isDartGeneratedFile(_ path: String) -> Bool {
        generatedDartFileSuffixes.contains(where: { path.hasSuffix($0) })
    }

    /// Returns `true` when the type name matches common Dart code-generation
    /// naming patterns (e.g. `_$MyClass`, `$MyClassCopyWith`, `_MyClass`).
    private static func isDartGeneratedTypeName(_ name: String) -> Bool {
        // _$ClassName — freezed implementation classes
        if name.hasPrefix("_$") { return true }
        // $ClassNameCopyWith — freezed copy-with interfaces
        if name.hasPrefix("$") && name.hasSuffix("CopyWith") { return true }
        return false
    }

    /// Returns a new artifact with Dart generated types (and their relationships) removed.
    ///
    /// Filtering is based on two heuristics:
    /// 1. **Source file**: types whose `location.filePath` ends with a known generated
    ///    suffix (`.freezed.dart`, `.g.dart`, etc.) are removed.
    /// 2. **Type name**: types matching code-generation naming patterns
    ///    (e.g. `_$Foo`, `$FooCopyWith`) are removed.
    public func filteringGeneratedDartTypes() -> CodeArtifact {
        let removedIDs: Set<String> = Set(
            types.filter { type in
                if let path = type.location?.filePath, Self.isDartGeneratedFile(path) {
                    return true
                }
                return Self.isDartGeneratedTypeName(type.name)
            }.map(\.id)
        )

        let removedNames: Set<String> = Set(
            types.filter { removedIDs.contains($0.id) }.map(\.name)
        )

        let filteredTypes = types.filter { !removedIDs.contains($0.id) }
        let filteredRelationships = relationships.filter { rel in
            !removedIDs.contains(rel.source) && !removedIDs.contains(rel.target)
                && !removedNames.contains(rel.source) && !removedNames.contains(rel.target)
        }

        return CodeArtifact(
            metadata: metadata,
            types: filteredTypes,
            relationships: filteredRelationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }
}
