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
}
