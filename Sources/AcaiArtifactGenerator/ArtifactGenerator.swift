import AcaiCore

/// Builds a random-but-valid `CodeArtifact` from a seed, for property-based tests: type ids are
/// unique, a relationship's endpoints name types that exist (or, deliberately sometimes, ones that
/// don't — an external reference is a normal artifact), and nesting, members, enum cases and
/// call sites are all populated.
///
/// The same seed always yields the same artifact, so a failing test reports its seed and the failure
/// is replayable with `ArtifactGenerator(seed:)`.
public struct ArtifactGenerator: Sendable {
    public let seed: UInt64
    private let alphabet: TypeNameAlphabet
    private let typeCount: ClosedRange<Int>

    public init(seed: UInt64, typeCount: ClosedRange<Int> = 1...12, alphabet: TypeNameAlphabet = .standard) {
        self.seed = seed
        self.typeCount = typeCount
        self.alphabet = alphabet
    }

    public func makeArtifact() -> CodeArtifact {
        var random = SeededGenerator(seed: seed)
        var namer = TypeNamer(alphabet: alphabet)

        let count = random.int(in: typeCount)
        var types: [TypeDeclaration] = []
        for _ in 0..<count {
            types.append(makeType(random: &random, namer: &namer, depth: 0))
        }

        let identifiers = namer.assignedIDs
        let relationshipCount = random.int(in: 0...(count * 2))
        var relationships: [Relationship] = []
        for _ in 0..<relationshipCount {
            relationships.append(makeRelationship(random: &random, identifiers: identifiers, namer: &namer))
        }

        return CodeArtifact(
            metadata: CodeArtifact.Metadata(
                sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift"),
                filePaths: identifiers.map { "Sources/Generated/\($0.hashValue.magnitude % 1000).swift" },
                toolVersion: "generator-\(seed)"
            ),
            types: types,
            relationships: relationships,
            freestandingFunctions: (0..<random.int(in: 0...3)).map { index in
                makeMember(random: &random, namer: &namer, kind: .method, nameSuffix: "free\(index)")
            },
            globalVariables: (0..<random.int(in: 0...2)).map { index in
                makeMember(random: &random, namer: &namer, kind: .property, nameSuffix: "global\(index)")
            }
        )
    }

    // MARK: - Types

    private func makeType(
        random: inout SeededGenerator, namer: inout TypeNamer, depth: Int
    ) -> TypeDeclaration {
        let name = namer.nextName(random: &random)
        let namespace = namer.currentNamespace
        let identifier = namer.assignID(name: name, namespace: namespace)
        let kind = random.pick(TypeKind.allCases) ?? .class

        // Extensions are generated only at the top level and always target a type that exists: an
        // extension of an unknown type is dropped by enrichment, which is its own (tested) behaviour.
        let extensionOf = kind == .extension && depth == 0 ? namer.assignedIDs.first : nil

        let nested: [TypeDeclaration]
        if depth < 2, random.bool(probability: 0.3) {
            namer.push(namespace: identifier)
            nested = (0...random.int(in: 0...1)).map { _ in
                makeType(random: &random, namer: &namer, depth: depth + 1)
            }
            namer.pop()
        } else {
            nested = []
        }

        return TypeDeclaration(
            id: identifier,
            name: name,
            qualifiedName: namespace.map { "\($0).\(name)" } ?? name,
            kind: kind,
            accessLevel: random.pick(AccessLevel.allCases) ?? .internal,
            modifiers: random.picks(random.int(in: 0...3), from: Modifier.allCases, uniqueBy: \.rawValue),
            genericParameters: (0..<random.int(in: 0...2)).map { index in
                GenericParameter(name: "T\(index)", constraints: [
                    GenericConstraint(
                        kind: random.pick([.conformance, .superclass, .sameType]) ?? .conformance,
                        type: TypeReference(name: namer.anyName(random: &random)))
                ])
            },
            inheritedTypes: (0..<random.int(in: 0...2)).map { _ in
                TypeReference(name: namer.anyName(random: &random))
            },
            members: (0..<random.int(in: 0...5)).map { index in
                makeMember(random: &random, namer: &namer, kind: nil, nameSuffix: "m\(index)")
            },
            enumCases: kind == .enum ? makeEnumCases(random: &random, namer: &namer) : [],
            nestedTypes: nested,
            annotations: random.picks(
                random.int(in: 0...2), from: ["@Observable", "@Entity", "@MainActor", "@objc"], uniqueBy: \.self),
            extensionOf: extensionOf,
            namespace: namespace,
            location: SourceLocation(
                filePath: "Sources/Generated/\(name.isEmpty ? "Unnamed" : name).swift",
                line: random.int(in: 1...400),
                column: random.int(in: 1...40)
            ),
            sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")
        )
    }

    private func makeEnumCases(random: inout SeededGenerator, namer: inout TypeNamer) -> [EnumCase] {
        (0..<random.int(in: 0...3)).map { index in
            EnumCase(
                name: "case\(index)",
                rawValue: random.bool(probability: 0.3) ? "RAW\(index)" : nil,
                associatedValues: random.bool(probability: 0.3)
                    ? [Parameter(internalName: "value", type: TypeReference(name: namer.anyName(random: &random)))]
                    : []
            )
        }
    }

    // MARK: - Members

    private func makeMember(
        random: inout SeededGenerator, namer: inout TypeNamer, kind: MemberKind?, nameSuffix: String
    ) -> Member {
        let kind = kind ?? random.pick(MemberKind.allCases) ?? .method
        return Member(
            name: "member\(nameSuffix)",
            kind: kind,
            accessLevel: random.pick(AccessLevel.allCases) ?? .internal,
            setAccessLevel: random.bool(probability: 0.2) ? random.pick(AccessLevel.allCases) : nil,
            modifiers: random.picks(random.int(in: 0...3), from: Modifier.allCases, uniqueBy: \.rawValue),
            type: random.bool(probability: 0.85) ? makeTypeReference(random: &random, namer: &namer) : nil,
            parameters: (0..<random.int(in: 0...3)).map { index in
                Parameter(
                    externalName: random.bool(probability: 0.3) ? "with\(index)" : nil,
                    internalName: "p\(index)",
                    type: makeTypeReference(random: &random, namer: &namer),
                    isVariadic: random.bool(probability: 0.1)
                )
            },
            isComputed: random.bool(probability: 0.3),
            annotations: random.picks(random.int(in: 0...1), from: ["@Published", "@objc"], uniqueBy: \.self),
            location: SourceLocation(
                filePath: "Sources/Generated/Member.swift", line: random.int(in: 1...400), column: 1),
            callSites: (0..<random.int(in: 0...3)).map { index in
                CallSite(
                    receiver: random.pick([
                        .selfDispatch, .free, .unknown, .type(namer.anyName(random: &random))
                    ]) ?? .unknown,
                    methodName: "call\(index)"
                )
            },
            fieldReads: (0..<random.int(in: 0...2)).map { index in FieldAccess(name: "field\(index)") },
            referencedTypeNames: (0..<random.int(in: 0...2)).map { _ in namer.anyName(random: &random) },
            cyclomaticComplexity: random.bool(probability: 0.7) ? random.int(in: 1...25) : nil
        )
    }

    private func makeTypeReference(
        random: inout SeededGenerator, namer: inout TypeNamer
    ) -> TypeReference {
        let isCollection = random.bool(probability: 0.25)
        return TypeReference(
            name: isCollection ? "Array" : namer.anyName(random: &random),
            genericArguments: isCollection
                ? [TypeReference(name: namer.anyName(random: &random))]
                : [],
            isOptional: random.bool(probability: 0.2),
            isArray: isCollection
        )
    }

    // MARK: - Relationships

    private func makeRelationship(
        random: inout SeededGenerator, identifiers: [String], namer: inout TypeNamer
    ) -> Relationship {
        // Sometimes an endpoint deliberately names no declared type: an edge to an external supertype
        // is a normal artifact and enrichment has to leave it alone.
        func endpoint() -> String {
            random.bool(probability: 0.8)
                ? (random.pick(identifiers) ?? namer.anyName(random: &random))
                : namer.anyName(random: &random)
        }
        return Relationship(
            kind: random.pick(Relationship.Kind.allCases) ?? .dependency,
            source: endpoint(),
            target: endpoint(),
            sourceLabel: random.bool(probability: 0.2) ? "1" : nil,
            targetLabel: random.bool(probability: 0.2) ? "0..*" : nil,
            label: random.bool(probability: 0.3) ? "link" : nil,
            origin: "Sources/Generated/Edges.swift"
        )
    }
}
