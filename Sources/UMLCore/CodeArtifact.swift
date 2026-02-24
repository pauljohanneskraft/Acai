public struct CodeArtifact: Codable, Equatable, Hashable, Sendable {
    public var metadata: Metadata
    public var types: [TypeDeclaration]
    public var relationships: [Relationship]
    public var freestandingFunctions: [Member]

    public init(
        metadata: Metadata,
        types: [TypeDeclaration] = [],
        relationships: [Relationship] = [],
        freestandingFunctions: [Member] = []
    ) {
        self.metadata = metadata
        self.types = types
        self.relationships = relationships
        self.freestandingFunctions = freestandingFunctions
    }

    public struct Metadata: Codable, Equatable, Hashable, Sendable {
        public var sourceLanguage: SourceLanguage
        public var filePaths: [String]
        public var toolVersion: String?

        public init(
            sourceLanguage: SourceLanguage,
            filePaths: [String] = [],
            toolVersion: String? = nil
        ) {
            self.sourceLanguage = sourceLanguage
            self.filePaths = filePaths
            self.toolVersion = toolVersion
        }
    }

    public enum SourceLanguage: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        case swift
        case kotlin
        case java
        case typeScript
        case javaScript
    }
}

extension CodeArtifact {
    public func merging(with other: CodeArtifact) -> CodeArtifact {
        CodeArtifact(
            metadata: Metadata(
                sourceLanguage: metadata.sourceLanguage,
                filePaths: metadata.filePaths + other.metadata.filePaths,
                toolVersion: metadata.toolVersion ?? other.metadata.toolVersion
            ),
            types: types + other.types,
            relationships: relationships + other.relationships,
            freestandingFunctions: freestandingFunctions + other.freestandingFunctions
        )
    }

    public func resolvingExtensions() -> CodeArtifact {
        var resolvedTypes = types.filter { $0.kind != .extension }
        let extensions = types.filter { $0.kind == .extension }
        var resolvedRelationships = relationships

        for ext in extensions {
            guard let targetName = ext.extensionOf else { continue }
            if let index = resolvedTypes.firstIndex(where: { $0.name == targetName }) {
                resolvedTypes[index].members.append(contentsOf: ext.members)
                resolvedTypes[index].nestedTypes.append(contentsOf: ext.nestedTypes)
            } else {
                resolvedTypes.append(ext)
            }
            for inherited in ext.inheritedTypes {
                resolvedRelationships.append(
                    Relationship(kind: .conformance, source: targetName, target: inherited.name)
                )
            }
        }

        return CodeArtifact(
            metadata: metadata,
            types: resolvedTypes,
            relationships: resolvedRelationships,
            freestandingFunctions: freestandingFunctions
        )
    }
}
