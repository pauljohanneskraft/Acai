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
        /// Concrete parse problems (location + kind + message) gathered while parsing.
        /// Empty when every source file parsed cleanly.
        public var parseDiagnostics: [ParseDiagnostic]

        /// `true` when at least one source file could not be fully parsed
        /// (the best-effort tree contained missing/unexpected nodes).
        public var hasParseErrors: Bool { !parseDiagnostics.isEmpty }

        public init(
            sourceLanguage: SourceLanguage,
            filePaths: [String] = [],
            toolVersion: String? = nil,
            parseDiagnostics: [ParseDiagnostic] = []
        ) {
            self.sourceLanguage = sourceLanguage
            self.filePaths = filePaths
            self.toolVersion = toolVersion
            self.parseDiagnostics = parseDiagnostics
        }
    }

    /// An open identifier for a source language.
    ///
    /// Deliberately a `RawRepresentable` struct rather than an enum: the built-in constants
    /// (`.swift`, `.dart`, …) are defined in their respective language targets, never here, so an
    /// agnostic target cannot name a specific language (it won't compile) and an external consumer
    /// can introduce a brand-new language with `SourceLanguage(rawValue:)`. Single-value `Codable`
    /// over `rawValue` keeps the JSON wire format identical to the former `String`-backed enum.
    public struct SourceLanguage: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}

extension CodeArtifact {
    /// A copy with every type (and nested type) stamped with `language`. Applied per language group
    /// during enrichment so each type in a merged polyglot artifact records where it came from.
    public func stampingSourceLanguage(_ language: SourceLanguage) -> CodeArtifact {
        var copy = self
        copy.types = types.map { $0.stampingSourceLanguage(language) }
        return copy
    }

    public func merging(with other: CodeArtifact) -> CodeArtifact {
        CodeArtifact(
            metadata: Metadata(
                sourceLanguage: metadata.sourceLanguage,
                filePaths: metadata.filePaths + other.metadata.filePaths,
                toolVersion: metadata.toolVersion ?? other.metadata.toolVersion,
                parseDiagnostics: metadata.parseDiagnostics + other.metadata.parseDiagnostics
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
                // Provenance: the conformance is declared by the *extension*, so a cross-module
                // extension (e.g. UMLDiff conforming a UMLDiagram type to a UMLDiff protocol) is
                // attributed to the extension's module — not the extended type's — for coupling/cycles.
                resolvedRelationships.append(
                    Relationship(
                        kind: .conformance, source: targetId, target: inherited.name,
                        origin: ext.location?.filePath)
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

    // MARK: - Generated-Code Filtering

    /// Returns a new artifact with each language's generated types (and their relationships) removed.
    ///
    /// The `resolver` supplies each type's `GeneratedCodeFilter` from *its own* language, so a polyglot
    /// artifact filters each language's generated files (e.g. Dart's `.freezed.dart`, Python's stubs)
    /// under that language's rules rather than one dominant filter. Stays language-agnostic: the engine
    /// applies filters it is handed and never knows which language produced them.
    public func filteringGeneratedTypes(using resolver: LanguageConfigurationResolver) -> CodeArtifact {
        let removedIDs: Set<String> = Set(
            types.filter { type in
                guard let filter = resolver.configuration(for: type).generatedCodeFilter else { return false }
                if let path = type.location?.filePath, filter.matchesFile(path) {
                    return true
                }
                return filter.matchesTypeName(type.name)
            }.map(\.id)
        )

        let removedNames: Set<String> = Set(
            types.filter { removedIDs.contains($0.id) }.map(\.name)
        )

        let filteredTypes = types.filter { !removedIDs.contains($0.id) }

        // Edges to a removed type may still reference it by *name* (e.g. an unresolved external
        // type). Remove those by name too — but only for names no surviving type claims, so a
        // generated type doesn't take down a legitimately-kept type that shares its simple name.
        let survivingNames = Set(filteredTypes.map(\.name))
        let removedOnlyNames = removedNames.subtracting(survivingNames)
        let filteredRelationships = relationships.filter { rel in
            !removedIDs.contains(rel.source) && !removedIDs.contains(rel.target)
                && !removedOnlyNames.contains(rel.source) && !removedOnlyNames.contains(rel.target)
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
