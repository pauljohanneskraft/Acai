import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("Class Diagram DOT Renderer Tests")
struct ClassDiagramDOTRendererTests {

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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("digraph UML"))
        #expect(dot.contains("Animal"))
        #expect(dot.contains("name"))
        #expect(dot.contains("speak"))
        #expect(dot.contains("String"))
    }

    @Test func multiplicityHeadLabelAndToggle() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: ["Player", "Track"].map {
                TypeDeclaration(id: $0, name: $0, qualifiedName: $0, kind: .class)
            },
            relationships: [
                Relationship(kind: .composition, source: "Player", target: "Track",
                             targetLabel: "0..1", label: "nowPlaying")
            ]
        )
        #expect(ClassDiagramDOTRenderer().generate(from: artifact).contains("headlabel=\"0..1\""))

        let options = ClassDiagramOptions(showMultiplicities: false)
        #expect(!ClassDiagramDOTRenderer(options: options).generate(from: artifact).contains("headlabel"))
    }

    @Test func annotationStereotypeInHeader() {
        var entity = TypeDeclaration(id: "User", name: "User", qualifiedName: "User", kind: .class)
        entity.annotations = ["@Entity"]
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .java, filePaths: ["U.java"]), types: [entity])
        #expect(ClassDiagramDOTRenderer().generate(from: artifact).contains("&lt;&lt;entity&gt;&gt;"))
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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("style=dashed"))
    }

    @Test func interfaceStereotype() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: ["Repo.kt"]),
            types: [
                TypeDeclaration(id: "Repo", name: "Repo", qualifiedName: "Repo", kind: .interface)
            ]
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("+ pub"))
        #expect(dot.contains("- priv"))
    }

    @Test func layoutDirection() {
        let options = ClassDiagramOptions(layoutDirection: .leftToRight)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class)]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(dot.contains("rankdir=LR"))
    }

    @Test func darkTheme() {
        let options = ClassDiagramOptions(theme: .dark)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class)]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(dot.contains("#1e1e1e"))
    }

    @Test func hideMembersOption() {
        let options = ClassDiagramOptions(showMembers: false)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class,
                    members: [Member(name: "bar", kind: .property)]
                )
            ]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(!dot.contains("bar"))
    }

    @Test func filterRelationshipKinds() {
        let options = ClassDiagramOptions(includedRelationshipKinds: [.inheritance])
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
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
        #expect(dot.contains("\"A\" -> \"C\""))
        #expect(!dot.contains("\"A\" -> \"B\""))
    }

    @Test func clusterByFile() {
        let options = ClassDiagramOptions(groupBy: .byFile)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class,
                                location: SourceLocation(filePath: "A.swift", line: 1, column: 1)),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class,
                                location: SourceLocation(filePath: "B.swift", line: 1, column: 1))
            ]
        )
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
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
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("Box&lt;T&gt;"))
    }

    @Test func emptyArtifact() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [])
        )
        let dot = ClassDiagramDOTRenderer().generate(from: artifact)
        #expect(dot.contains("digraph UML"))
        #expect(dot.contains("}"))
    }

}
