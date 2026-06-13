import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("Mermaid Renderers")
struct MermaidRendererTests {

    // MARK: - Class diagram

    private func classArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Zoo.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    members: [
                        Member(name: "name", kind: .property, accessLevel: .public,
                               type: TypeReference(name: "String")),
                        Member(
                            name: "tags", kind: .property, accessLevel: .private,
                            type: TypeReference(name: "Array", genericArguments: [TypeReference(name: "String")])
                        ),
                        Member(name: "speak", kind: .method, accessLevel: .public,
                               type: TypeReference(name: "String"))
                    ]
                ),
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class),
                TypeDeclaration(id: "Pet", name: "Pet", qualifiedName: "Pet", kind: .protocol),
                TypeDeclaration(id: "Cat", name: "Cat", qualifiedName: "Cat", kind: .class)
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "Dog", target: "Animal"),
                Relationship(kind: .conformance, source: "Cat", target: "Pet")
            ]
        )
    }

    @Test func classDiagramHeaderAndMembers() {
        let mermaid = ClassDiagramMermaidRenderer().generate(from: classArtifact())
        #expect(mermaid.hasPrefix("classDiagram\n"))
        #expect(mermaid.contains("class Animal[\"Animal\"]"))
        #expect(mermaid.contains("+name String"))
        #expect(mermaid.contains("+speak() String"))
    }

    @Test func classDiagramUsesTildeGenerics() {
        let mermaid = ClassDiagramMermaidRenderer().generate(from: classArtifact())
        // Angle-bracket generics become Mermaid tilde notation so they don't break parsing.
        #expect(mermaid.contains("Array~String~"))
        #expect(!mermaid.contains("Array<String>"))
    }

    @Test func classDiagramRelationshipsKeepOrientation() {
        let mermaid = ClassDiagramMermaidRenderer().generate(from: classArtifact())
        // Inheritance: parent <|-- child. Conformance (realization): interface <|.. impl.
        #expect(mermaid.contains("Animal <|-- Dog"))
        #expect(mermaid.contains("Pet <|.. Cat"))
    }

    // MARK: - Sequence diagram

    @Test func sequenceDiagramMessagesAndReturns() {
        let diagram = SequenceDiagram(
            title: "Login",
            participants: [
                .init(id: "LoginService", name: "LoginService", kind: .control),
                .init(id: "AuthService", name: "AuthService", kind: .object)
            ],
            messages: [
                .init(from: "LoginService", to: "AuthService", label: "authenticate", kind: .synchronous, order: 0),
                .init(from: "AuthService", to: "LoginService", label: nil, kind: .return, order: 1)
            ]
        )
        let mermaid = SequenceDiagramMermaidRenderer().render(diagram)
        #expect(mermaid.hasPrefix("sequenceDiagram\n"))
        #expect(mermaid.contains("participant LoginService as LoginService"))
        #expect(mermaid.contains("LoginService->>AuthService: authenticate"))
        #expect(mermaid.contains("AuthService-->>LoginService:"))
    }

    // MARK: - State diagram

    @Test func stateDiagramInitialAndTransitions() {
        let diagram = StateDiagram(
            title: "Loader.state",
            states: [
                .init(id: "__initial", name: "", kind: .initial),
                .init(id: "state_idle", name: "idle", kind: .normal),
                .init(id: "state_loading", name: "loading", kind: .normal)
            ],
            transitions: [
                .init(from: "__initial", to: "state_idle"),
                .init(from: "state_idle", to: "state_loading", event: "load()")
            ]
        )
        let mermaid = StateDiagramMermaidRenderer().render(diagram)
        #expect(mermaid.hasPrefix("stateDiagram-v2\n"))
        #expect(mermaid.contains("state \"idle\" as state_idle"))
        #expect(mermaid.contains("[*] --> state_idle"))
        #expect(mermaid.contains("state_idle --> state_loading : load()"))
    }
}
