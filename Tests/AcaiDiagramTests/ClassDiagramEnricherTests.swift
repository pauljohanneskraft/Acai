import Testing
@testable import AcaiDiagram
@testable import AcaiCore

@Suite("Class Diagram Enricher Tests")
struct ClassDiagramEnricherTests {

    @Test func compositionInferredFromProperty() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class,
                    accessLevel: .public),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "engine", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(name: "Engine"))
                    ]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("\"Car\" -> \"Engine\""))
        #expect(dot.contains("arrowtail=diamond"))
    }

    @Test func aggregationInferredFromCollectionProperty() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Wheel", name: "Wheel", qualifiedName: "Wheel", kind: .class, accessLevel: .public),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "wheels", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(name: "Wheel", isArray: true))
                    ]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("\"Car\" -> \"Wheel\""))
        #expect(dot.contains("arrowtail=odiamond"))
    }

    @Test func dependencyInferredFromMethodParameter() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Logger", name: "Logger", qualifiedName: "Logger", kind: .class,
                    accessLevel: .public),
                TypeDeclaration(
                    id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "doWork", kind: .method,
                               accessLevel: .internal,
                               parameters: [
                                Parameter(internalName: "logger", type: TypeReference(name: "Logger"))
                               ])
                    ]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("\"Service\" -> \"Logger\""))
        #expect(dot.contains("style=dashed"))
    }

    @Test func externalTypesShownWhenEnabled() {
        let options = ClassDiagramOptions(showExternalTypes: true)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class, accessLevel: .public)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "ExternalBase")
            ]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(dot.contains("ExternalBase"))
        #expect(dot.contains("#E8E8E8")) // external node gray fill
    }

    @Test func externalTypesHiddenByDefault() {
        // Parser-produced edges (inheritance) to external types are always kept,
        // but INFERRED edges (composition) to external types are filtered.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class,
                                accessLevel: .public,
                                members: [
                                    Member(name: "collar", kind: .property,
                                           accessLevel: .internal,
                                           type: TypeReference(name: "ExternalCollar"))
                                ])
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "ExternalBase")
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        // Inheritance to ExternalBase is kept (parser-produced); composition to ExternalCollar is
        // filtered (inferred, external target) — no separate node or edge for it.
        #expect(dot.contains("ExternalBase"))
        #expect(!dot.contains("\"ExternalCollar\""))
    }

    @Test func redundantEdgesRemoved() {
        // If Dog inherits from Animal, a composition edge Dog→Animal should be suppressed.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    accessLevel: .public),
                TypeDeclaration(
                    id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "parent", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(name: "Animal"))
                    ]
                )
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "Animal")
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("arrowhead=empty"))
        // No composition edge — redundant with inheritance.
        #expect(!dot.contains("arrowtail=diamond"))
    }

    @Test func clusterByDirectory() {
        let options = ClassDiagramOptions(groupBy: .byDirectory)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["models/A.swift", "views/B.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class,
                                accessLevel: .public,
                                location: SourceLocation(filePath: "models/A.swift", line: 1, column: 1)),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class,
                                accessLevel: .public,
                                location: SourceLocation(filePath: "views/B.swift", line: 1, column: 1))
            ]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(dot.contains("subgraph cluster_dir_"))
        #expect(dot.contains("models"))
        #expect(dot.contains("views"))
    }

    @Test func nestedTypesFlattened() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .class,
                    accessLevel: .public,
                    nestedTypes: [
                        TypeDeclaration(id: "Inner", name: "Inner", qualifiedName: "Outer.Inner",
                                        kind: .class, accessLevel: .public)
                    ]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("Outer"))
        #expect(dot.contains("Inner"))
    }

    @Test func qualifiedIdResolution() {
        // Even when relationships use simple names, they should connect to types with qualified IDs.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Server.kt"]),
            types: [
                TypeDeclaration(id: "com.example.Base", name: "Base",
                                qualifiedName: "com.example.Base", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "com.example.Child", name: "Child",
                                qualifiedName: "com.example.Child", kind: .class, accessLevel: .public)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Child", target: "Base")
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("\"com.example.Child\" -> \"com.example.Base\""))
    }

    @Test func compositionTypeInPropertyProducesIndividualEdges() {
        // A property typed `Drawable & Printable` creates edges to both types: the parser stores
        // composition components as genericArguments on the TypeReference.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Drawable", name: "Drawable", qualifiedName: "Drawable", kind: .protocol,
                    accessLevel: .public),
                TypeDeclaration(id: "Printable", name: "Printable", qualifiedName: "Printable", kind: .protocol,
                                accessLevel: .public),
                TypeDeclaration(
                    id: "Box", name: "Box", qualifiedName: "Box", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "value", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(
                                   name: "Drawable & Printable",
                                   genericArguments: [
                                       TypeReference(name: "Drawable"),
                                       TypeReference(name: "Printable")
                                   ]
                               ))
                    ]
                )
            ]
        )
        let result = ClassDiagram(artifact)
        let boxEdges = result.relationships.filter { $0.source == "Box" }
        let targets = Set(boxEdges.map(\.target))
        #expect(targets.contains("Drawable"))
        #expect(targets.contains("Printable"))
    }

    @Test func compositionDisabledByOption() {
        let options = ClassDiagramOptions(inferCompositionFromProperties: false)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class,
                    accessLevel: .public),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "engine", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(name: "Engine"))
                    ]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(!dot.contains("arrowtail=diamond"))
    }

    @Test func crossFileRelationshipsResolvedByEnricher() {
        // Two Kotlin files parsed separately and merged: after merging, the relationship target
        // "Animal" (simple name from source text) must resolve to "com.example.Animal" (qualified ID).
        let file1 = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Animal.kt"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Animal", name: "Animal",
                    qualifiedName: "com.example.Animal", kind: .class,
                    accessLevel: .public,
                    namespace: "com.example"
                )
            ]
        )
        let file2 = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Dog.kt"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Dog", name: "Dog",
                    qualifiedName: "com.example.Dog", kind: .class,
                    accessLevel: .public,
                    inheritedTypes: [TypeReference(name: "Animal")],
                    namespace: "com.example"
                )
            ],
            // Parser creates relationship with simple name for cross-file target.
            relationships: [
                Relationship(kind: .inheritance, source: "com.example.Dog", target: "Animal")
            ]
        )

        let merged = file1.merging(with: file2)
        let result = ClassDiagram(merged)

        let inheritance = result.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        #expect(inheritance?.target == "com.example.Animal")

        let ids = Set(result.types.map(\.id))
        #expect(ids.contains("com.example.Dog"))
        #expect(ids.contains("com.example.Animal"))
    }

    @Test func multiFilePropertyEdgesResolved() {
        // A property type reference to a type from a different file.
        let file1 = CodeArtifact(
            metadata: .init(sourceLanguage: .java, filePaths: ["Engine.java"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Engine", name: "Engine",
                    qualifiedName: "com.example.Engine", kind: .class,
                    accessLevel: .public,
                    namespace: "com.example"
                )
            ]
        )
        let file2 = CodeArtifact(
            metadata: .init(sourceLanguage: .java, filePaths: ["Car.java"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Car", name: "Car",
                    qualifiedName: "com.example.Car", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "engine", kind: .property,
                               accessLevel: .internal,
                               type: TypeReference(name: "Engine"))
                    ],
                    namespace: "com.example"
                )
            ]
        )

        let merged = file1.merging(with: file2)
        let result = ClassDiagram(merged)

        let compositions = result.relationships.filter {
            $0.kind == .composition && $0.source == "com.example.Car"
        }
        #expect(compositions.contains { $0.target == "com.example.Engine" })
    }
}
