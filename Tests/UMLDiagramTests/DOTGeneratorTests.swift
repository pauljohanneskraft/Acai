import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("DOT Generator Tests")
struct DOTGeneratorTests {

    @Test func simpleClassDiagram() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "name", kind: .property, accessLevel: .public,
                               type: TypeReference(name: "String")),
                        Member(name: "speak", kind: .method, accessLevel: .public,
                               type: TypeReference(name: "String"))
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("digraph UML"))
        #expect(dot.contains("Animal"))
        #expect(dot.contains("name"))
        #expect(dot.contains("speak"))
        #expect(dot.contains("String"))
    }

    @Test func inheritanceEdge() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class),
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "Animal")
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("\"Dog\" -> \"Animal\""))
        #expect(dot.contains("arrowhead=empty"))
        #expect(dot.contains("style=solid"))
    }

    @Test func conformanceEdge() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class),
                TypeDeclaration(id: "Bar", name: "Bar", qualifiedName: "Bar", kind: .protocol)
            ],
            relationships: [
                Relationship(kind: .conformance, source: "Foo", target: "Bar")
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("style=dashed"))
    }

    @Test func interfaceStereotype() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Repo.kt"]),
            types: [
                TypeDeclaration(id: "Repo", name: "Repo", qualifiedName: "Repo", kind: .interface)
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("interface"))
    }

    @Test func enumStereotype() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Dir.swift"]),
            types: [
                TypeDeclaration(
                    id: "Direction", name: "Direction", qualifiedName: "Direction", kind: .enum,
                    enumCases: [
                        EnumCase(name: "north"),
                        EnumCase(name: "south")
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("enumeration"))
        #expect(dot.contains("north"))
        #expect(dot.contains("south"))
    }

    @Test func accessLevelSymbols() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class,
                    members: [
                        Member(name: "pub", kind: .property, accessLevel: .public,
                               type: TypeReference(name: "Int")),
                        Member(name: "priv", kind: .property, accessLevel: .private,
                               type: TypeReference(name: "Int"))
                    ]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("+ pub"))
        #expect(dot.contains("- priv"))
    }

    @Test func layoutDirection() {
        let options = DiagramOptions(layoutDirection: .leftToRight)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class)]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(dot.contains("rankdir=LR"))
    }

    @Test func darkTheme() {
        let options = DiagramOptions(theme: .dark)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class)]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(dot.contains("#1e1e1e"))
    }

    @Test func hideMembersOption() {
        let options = DiagramOptions(showMembers: false)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class,
                    members: [Member(name: "bar", kind: .property)]
                )
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(!dot.contains("bar"))
    }

    @Test func filterRelationshipKinds() {
        let options = DiagramOptions(includedRelationshipKinds: [.inheritance])
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .protocol),
                TypeDeclaration(id: "C", name: "C", qualifiedName: "C", kind: .class)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "A", target: "C"),
                Relationship(kind: .conformance, source: "A", target: "B")
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(dot.contains("\"A\" -> \"C\""))
        #expect(!dot.contains("\"A\" -> \"B\""))
    }

    @Test func clusterByFile() {
        let options = DiagramOptions(groupBy: .byFile)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class,
                                location: SourceLocation(filePath: "A.swift", line: 1, column: 1)),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class,
                                location: SourceLocation(filePath: "B.swift", line: 1, column: 1))
            ]
        )
        let dot = DOTGenerator(options: options).generate(from: artifact)
        #expect(dot.contains("subgraph cluster_"))
        #expect(dot.contains("A.swift"))
        #expect(dot.contains("B.swift"))
    }

    @Test func genericParameters() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Box", name: "Box", qualifiedName: "Box", kind: .class,
                    genericParameters: [GenericParameter(name: "T")]
                )
            ]
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("Box&lt;T&gt;"))
    }

    @Test func emptyArtifact() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [])
        )
        let dot = DOTGenerator().generate(from: artifact)
        #expect(dot.contains("digraph UML"))
        #expect(dot.contains("}"))
    }

    // MARK: - Enricher Integration Tests

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
        let options = DiagramOptions(showExternalTypes: true)
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
        #expect(!dot.contains("ExternalCollar"))
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
        let options = DiagramOptions(groupBy: .byDirectory)
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

    @Test func compositionDisabledByOption() {
        let options = DiagramOptions(inferCompositionFromProperties: false)
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
}
