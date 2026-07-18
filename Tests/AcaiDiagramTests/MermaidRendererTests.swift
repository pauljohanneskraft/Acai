import Testing
@testable import AcaiDiagram
@testable import AcaiCore

@Suite("Mermaid Renderers")
struct MermaidRendererTests {

    // MARK: - Class diagram

    private func classArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Zoo.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    accessLevel: .public,
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
                TypeDeclaration(id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "Pet", name: "Pet", qualifiedName: "Pet", kind: .protocol, accessLevel: .public),
                TypeDeclaration(id: "Cat", name: "Cat", qualifiedName: "Cat", kind: .class, accessLevel: .public)
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

    @Test func classDiagramStructuralArrows() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: ["A", "B", "C", "D", "E"].map {
                TypeDeclaration(id: $0, name: $0, qualifiedName: $0, kind: .class, accessLevel: .public)
            },
            relationships: [
                Relationship(kind: .composition, source: "A", target: "B"),
                Relationship(kind: .aggregation, source: "A", target: "C"),
                Relationship(kind: .association, source: "A", target: "D"),
                Relationship(kind: .dependency, source: "B", target: "C"),
                Relationship(kind: .nesting, source: "D", target: "E")
            ]
        )
        let mermaid = ClassDiagramMermaidRenderer().generate(from: artifact)
        #expect(mermaid.contains("A *-- B"))   // composition
        #expect(mermaid.contains("A o-- C"))   // aggregation
        #expect(mermaid.contains("A --> D"))   // association
        #expect(mermaid.contains("B ..> C"))   // dependency
        #expect(mermaid.contains("D *-- E"))   // nesting (containment)
    }

    private func multiplicityArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: ["Library", "Book"].map {
                TypeDeclaration(id: $0, name: $0, qualifiedName: $0, kind: .class, accessLevel: .public)
            },
            relationships: [
                Relationship(kind: .aggregation, source: "Library", target: "Book",
                             targetLabel: "*", label: "books")
            ]
        )
    }

    @Test func classDiagramEmitsMultiplicities() {
        let mermaid = ClassDiagramMermaidRenderer().generate(from: multiplicityArtifact())
        #expect(mermaid.contains("Library o-- \"*\" Book : books"))
    }

    @Test func classDiagramOmitsMultiplicitiesWhenDisabled() {
        let options = ClassDiagramOptions(showMultiplicities: false)
        let mermaid = ClassDiagramMermaidRenderer(options: options).generate(from: multiplicityArtifact())
        #expect(mermaid.contains("Library o-- Book : books"))
        #expect(!mermaid.contains("\"*\""))
    }

    @Test func classDiagramEmitsAnnotationStereotype() {
        var entity = TypeDeclaration(id: "User", name: "User", qualifiedName: "User", kind: .class,
            accessLevel: .public)
        entity.annotations = ["@Entity"]
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .java, filePaths: ["U.java"]), types: [entity])

        #expect(ClassDiagramMermaidRenderer().generate(from: artifact).contains("<<entity>>"))

        let options = ClassDiagramOptions(showAnnotationStereotypes: false)
        #expect(!ClassDiagramMermaidRenderer(options: options).generate(from: artifact).contains("<<entity>>"))
    }

    @Test func classDiagramEnumCasesAndModifiers() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: [
                TypeDeclaration(
                    id: "Genre", name: "Genre", qualifiedName: "Genre", kind: .enum,
                    accessLevel: .public,
                    members: [
                        Member(name: "shared", kind: .property, accessLevel: .public,
                               modifiers: [.static], type: TypeReference(name: "Int")),
                        Member(name: "play", kind: .method, accessLevel: .public, modifiers: [.abstract])
                    ],
                    enumCases: [EnumCase(name: "rock"), EnumCase(name: "jazz")]
                )
            ]
        )
        let mermaid = ClassDiagramMermaidRenderer().generate(from: artifact)
        #expect(mermaid.contains("<<enumeration>>"))
        #expect(mermaid.contains("rock"))
        #expect(mermaid.contains("jazz"))
        #expect(mermaid.contains("+shared Int$"))  // static → $ suffix
        #expect(mermaid.contains("+play()*"))        // abstract → * suffix
    }

    @Test func classDiagramGenericsInClassName() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: [
                TypeDeclaration(id: "Box", name: "Box", qualifiedName: "Box", kind: .struct,
                                accessLevel: .public,
                                genericParameters: [GenericParameter(name: "T")])
            ]
        )
        let mermaid = ClassDiagramMermaidRenderer().generate(from: artifact)
        #expect(mermaid.contains("class Box[\"Box<T>\"]"))
        #expect(mermaid.contains("<<struct>>"))
    }

    @Test func classDiagramRendersExternalTypesWhenEnabled() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public)],
            relationships: [Relationship(kind: .dependency, source: "A", target: "ExternalThing")]
        )
        var options = ClassDiagramOptions()
        options.showExternalTypes = true
        let mermaid = ClassDiagramMermaidRenderer(options: options).generate(from: artifact)
        #expect(mermaid.contains("ExternalThing"))
    }

    @Test func classDiagramRelationshipLabel() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public)
            ],
            relationships: [Relationship(kind: .association, source: "A", target: "B", label: "uses")]
        )
        let mermaid = ClassDiagramMermaidRenderer().generate(from: artifact)
        #expect(mermaid.contains("A --> B : uses"))
    }

    @Test func classDiagramPlainClassHasNoBody() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["X.swift"]),
            types: [TypeDeclaration(id: "Empty", name: "Empty", qualifiedName: "Empty", kind: .class,
                accessLevel: .public)]
        )
        let mermaid = ClassDiagramMermaidRenderer().generate(from: artifact)
        #expect(mermaid.contains("class Empty[\"Empty\"]"))
        #expect(!mermaid.contains("class Empty[\"Empty\"] {"))
    }

    @Test func classDiagramHonoursMemberToggles() {
        var hideMembers = ClassDiagramOptions()
        hideMembers.showMembers = false
        #expect(!ClassDiagramMermaidRenderer(options: hideMembers).generate(from: classArtifact())
            .contains("+name"))

        var hideTypes = ClassDiagramOptions()
        hideTypes.showMemberTypes = false
        let mermaid = ClassDiagramMermaidRenderer(options: hideTypes).generate(from: classArtifact())
        #expect(mermaid.contains("+name"))
        #expect(!mermaid.contains("+name String"))
        #expect(mermaid.contains("+speak()"))
    }

    @Test func classDiagramRespectsMinimumAccessLevel() {
        var options = ClassDiagramOptions()
        options.minimumAccessLevel = .public
        let mermaid = ClassDiagramMermaidRenderer(options: options).generate(from: classArtifact())
        // `tags` is private and filtered out; public `name` survives.
        #expect(mermaid.contains("+name"))
        #expect(!mermaid.contains("tags"))
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
        // A `.control` participant carries its UML stereotype above the name (matching DOT); a plain
        // `.object` participant does not.
        #expect(mermaid.contains("participant LoginService as «control»<br/>LoginService"))
        #expect(mermaid.contains("participant AuthService as AuthService"))
        #expect(mermaid.contains("LoginService->>AuthService: authenticate"))
        #expect(mermaid.contains("AuthService-->>LoginService:"))
    }

    @Test func sequenceDiagramMessageKinds() {
        let diagram = SequenceDiagram(
            participants: [
                .init(id: "A", name: "A", kind: .control),
                .init(id: "B", name: "B", kind: .object)
            ],
            messages: [
                .init(from: "A", to: "B", label: "make", kind: .create, order: 0),
                .init(from: "A", to: "B", label: "ping", kind: .asynchronous, order: 1),
                .init(from: "A", to: "B", label: "kill", kind: .destroy, order: 2)
            ]
        )
        let mermaid = SequenceDiagramMermaidRenderer().render(diagram)
        #expect(mermaid.contains("A-)B: ping"))        // asynchronous arrow
        #expect(mermaid.contains("«create» make"))
        #expect(mermaid.contains("«destroy» kill"))
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
