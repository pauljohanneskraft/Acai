import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("Class Diagram Enricher Tests")
struct ClassDiagramEnricherTests {

    @Test func compositionInferredFromProperty() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    members: [
                        Member(name: "engine", kind: .property,
                               type: TypeReference(name: "Engine"))
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        // Should have a composition edge from Car to Engine
        #expect(dot.contains("\"Car\" -> \"Engine\""))
        #expect(dot.contains("arrowtail=diamond"))
    }

    @Test func aggregationInferredFromCollectionProperty() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Wheel", name: "Wheel", qualifiedName: "Wheel", kind: .class),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    members: [
                        Member(name: "wheels", kind: .property,
                               type: TypeReference(name: "Wheel", isArray: true))
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        // Should have an aggregation edge from Car to Wheel
        #expect(dot.contains("\"Car\" -> \"Wheel\""))
        #expect(dot.contains("arrowtail=odiamond"))
    }

    @Test func dependencyInferredFromMethodParameter() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Logger", name: "Logger", qualifiedName: "Logger", kind: .class),
                TypeDeclaration(
                    id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
                    members: [
                        Member(name: "doWork", kind: .method,
                               parameters: [
                                Parameter(internalName: "logger", type: TypeReference(name: "Logger"))
                               ])
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("\"Service\" -> \"Logger\""))
        #expect(dot.contains("style=dashed"))
    }

    @Test func externalTypesShownWhenEnabled() {
        let options = ClassDiagramOptions(showExternalTypes: true)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "ExternalBase")
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        // External type should be rendered as a gray placeholder
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
                                members: [
                                    Member(name: "collar", kind: .property,
                                           type: TypeReference(name: "ExternalCollar"))
                                ])
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "ExternalBase")
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        // Inheritance edge to ExternalBase is KEPT (parser-produced).
        #expect(dot.contains("ExternalBase"))
        // Composition edge to ExternalCollar is FILTERED (inferred, external target).
        // The type name may still appear in the property label inside the Dog node,
        // but there must be no separate node or edge for it.
        #expect(!dot.contains("\"ExternalCollar\""))
    }

    @Test func redundantEdgesRemoved() {
        // If Dog inherits from Animal, a composition edge Dog→Animal should be suppressed.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class),
                TypeDeclaration(
                    id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class,
                    members: [
                        Member(name: "parent", kind: .property,
                               type: TypeReference(name: "Animal"))
                    ]
                )
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "Animal")
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        // Should have inheritance edge
        #expect(dot.contains("arrowhead=empty"))
        // Should NOT have composition edge (redundant with inheritance)
        #expect(!dot.contains("arrowtail=diamond"))
    }

    @Test func clusterByDirectory() {
        let options = ClassDiagramOptions(groupBy: .byDirectory)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["models/A.swift", "views/B.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class,
                                location: SourceLocation(filePath: "models/A.swift", line: 1, column: 1)),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class,
                                location: SourceLocation(filePath: "views/B.swift", line: 1, column: 1))
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
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
                    nestedTypes: [
                        TypeDeclaration(id: "Inner", name: "Inner", qualifiedName: "Outer.Inner",
                                        kind: .class)
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("Outer"))
        #expect(dot.contains("Inner"))
    }

    @Test func qualifiedIdResolution() {
        // Even when relationships use simple names, they should connect to types with qualified IDs.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Server.kt"]),
            types: [
                TypeDeclaration(id: "com.example.Base", name: "Base",
                                qualifiedName: "com.example.Base", kind: .class),
                TypeDeclaration(id: "com.example.Child", name: "Child",
                                qualifiedName: "com.example.Child", kind: .class)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Child", target: "Base")
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        // The enricher should resolve "Child" → "com.example.Child" and "Base" → "com.example.Base"
        #expect(dot.contains("\"com.example.Child\" -> \"com.example.Base\""))
    }

    @Test func compositionTypeInPropertyProducesIndividualEdges() {
        // A property typed `Drawable & Printable` should create edges to both types.
        // The parser stores composition components as genericArguments on the TypeReference,
        // so the enricher finds them via its existing recursive traversal.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Drawable", name: "Drawable", qualifiedName: "Drawable", kind: .protocol),
                TypeDeclaration(id: "Printable", name: "Printable", qualifiedName: "Printable", kind: .protocol),
                TypeDeclaration(
                    id: "Box", name: "Box", qualifiedName: "Box", kind: .class,
                    members: [
                        Member(name: "value", kind: .property,
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
        let result = ClassDiagramEnricher.enrich(artifact)
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
                TypeDeclaration(id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class),
                TypeDeclaration(
                    id: "Car", name: "Car", qualifiedName: "Car", kind: .class,
                    members: [
                        Member(name: "engine", kind: .property,
                               type: TypeReference(name: "Engine"))
                    ]
                )
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(!dot.contains("arrowtail=diamond"))
    }

    @Test func crossFileRelationshipsResolvedByEnricher() {
        // Simulates two Kotlin files parsed separately and merged:
        // File 1 defines Animal, File 2 defines Dog extending Animal.
        // After merging, the relationship target "Animal" (simple name from source text)
        // must be resolved to "com.example.Animal" (qualified ID) by the enricher.
        let file1 = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Animal.kt"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Animal", name: "Animal",
                    qualifiedName: "com.example.Animal", kind: .class,
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
        let result = ClassDiagramEnricher.enrich(merged)

        // Enricher must resolve "Animal" to "com.example.Animal".
        let inheritance = result.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        #expect(inheritance?.target == "com.example.Animal")

        // Both endpoints must be in the known types.
        let ids = Set(result.types.map(\.id))
        #expect(ids.contains("com.example.Dog"))
        #expect(ids.contains("com.example.Animal"))
    }

    @Test func multiFilePropertyEdgesResolved() {
        // Simulates a property type reference to a type from a different file.
        let file1 = CodeArtifact(
            metadata: .init(sourceLanguage: .java, filePaths: ["Engine.java"]),
            types: [
                TypeDeclaration(
                    id: "com.example.Engine", name: "Engine",
                    qualifiedName: "com.example.Engine", kind: .class,
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
                    members: [
                        Member(name: "engine", kind: .property,
                               type: TypeReference(name: "Engine"))
                    ],
                    namespace: "com.example"
                )
            ]
        )

        let merged = file1.merging(with: file2)
        let result = ClassDiagramEnricher.enrich(merged)

        // Enricher should infer a composition edge from Car to Engine.
        let compositions = result.relationships.filter {
            $0.kind == .composition && $0.source == "com.example.Car"
        }
        #expect(compositions.contains { $0.target == "com.example.Engine" })
    }
}
