import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("Sequence Diagram Generation")
struct SequenceDiagramTests {

    // MARK: - Fixtures

    /// A method member whose body makes the given calls.
    private func method(_ name: String, calls: [CallSite] = []) -> Member {
        Member(name: name, kind: .method, callSites: calls)
    }

    private func type(_ name: String, kind: TypeKind = .class, members: [Member]) -> TypeDeclaration {
        TypeDeclaration(id: name, name: name, qualifiedName: name, kind: kind, members: members)
    }

    private func artifact(types: [TypeDeclaration], relationships: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: types,
            relationships: relationships
        )
    }

    // MARK: - Basic call

    @Test func tracesSingleCrossTypeCall() {
        let art = artifact(types: [
            type("LoginService", members: [
                method("login", calls: [CallSite(receiverType: "AuthService", methodName: "authenticate")])
            ]),
            type("AuthService", members: [method("authenticate")])
        ])

        let diagram = art.sequenceDiagram(entryPoint: ("LoginService", "login"))

        #expect(diagram.participants.map(\.name) == ["LoginService", "AuthService"])
        // Synchronous call out, then a return back.
        #expect(diagram.messages.count == 2)
        let call = diagram.messages[0]
        #expect(call.from == "LoginService")
        #expect(call.to == "AuthService")
        #expect(call.label == "authenticate")
        #expect(call.kind == .synchronous)
        let ret = diagram.messages[1]
        #expect(ret.from == "AuthService")
        #expect(ret.to == "LoginService")
        #expect(ret.kind == .return)
        // Messages are strictly ordered top-to-bottom.
        #expect(diagram.messages.map(\.order) == [0, 1])
    }

    @Test func participantIDsMatchMessageEndpointsForNamespacedTypes() {
        // Kotlin/Java give types a qualified `id` (e.g. "shop.Checkout") distinct from the simple
        // name. Participants must key on the simple name the messages use, or every message is
        // orphaned (which previously left namespaced sequence diagrams empty in DOT/Mermaid).
        let checkout = TypeDeclaration(
            id: "shop.Checkout", name: "Checkout", qualifiedName: "shop.Checkout", kind: .class,
            members: [method("placeOrder", calls: [CallSite(receiverType: "PaymentService", methodName: "charge")])]
        )
        let service = TypeDeclaration(
            id: "shop.PaymentService", name: "PaymentService", qualifiedName: "shop.PaymentService",
            kind: .class, members: [method("charge")]
        )
        let diagram = artifact(types: [checkout, service]).sequenceDiagram(entryPoint: ("Checkout", "placeOrder"))

        let participantIDs = Set(diagram.participants.map(\.id))
        #expect(participantIDs == ["Checkout", "PaymentService"])
        #expect(!diagram.messages.isEmpty)
        for message in diagram.messages {
            #expect(participantIDs.contains(message.from), "orphaned message.from: \(message.from)")
            #expect(participantIDs.contains(message.to), "orphaned message.to: \(message.to)")
        }
    }

    @Test func messagesPreserveCallOrder() {
        let art = artifact(types: [
            type("Controller", members: [
                method("handle", calls: [
                    CallSite(receiverType: "Validator", methodName: "validate"),
                    CallSite(receiverType: "Store", methodName: "persist")
                ])
            ]),
            type("Validator", members: [method("validate")]),
            type("Store", members: [method("persist")])
        ])

        let diagram = art.sequenceDiagram(entryPoint: ("Controller", "handle"))

        // validate (+return) before persist (+return).
        let outbound = diagram.messages.filter { $0.kind == .synchronous }.map(\.label)
        #expect(outbound == ["validate", "persist"])
        #expect(diagram.messages.map(\.order) == Array(0..<diagram.messages.count))
        #expect(diagram.participants.map(\.name) == ["Controller", "Validator", "Store"])
    }

    // MARK: - Self calls

    @Test func selfCallStaysOnSameLifeline() {
        // A call with no resolvable receiver is treated as a self-message.
        let art = artifact(types: [
            type("Worker", members: [
                method("run", calls: [CallSite(receiverType: nil, methodName: "step")]),
                method("step")
            ])
        ])

        let diagram = art.sequenceDiagram(entryPoint: ("Worker", "run"))

        #expect(diagram.participants.map(\.name) == ["Worker"])
        let call = diagram.messages.first { $0.kind == .synchronous }
        #expect(call?.from == "Worker")
        #expect(call?.to == "Worker")
        #expect(call?.label == "step")
    }

    // MARK: - Depth / recursion

    @Test func maxDepthStopsExpansion() {
        // A -> B -> C -> D, but maxDepth 2 should stop expanding at C (D never appears).
        let art = artifact(types: [
            type("A", members: [method("a", calls: [CallSite(receiverType: "B", methodName: "b")])]),
            type("B", members: [method("b", calls: [CallSite(receiverType: "C", methodName: "c")])]),
            type("C", members: [method("c", calls: [CallSite(receiverType: "D", methodName: "d")])]),
            type("D", members: [method("d")])
        ])

        let diagram = art.sequenceDiagram(entryPoint: ("A", "a"), maxDepth: 2)

        #expect(diagram.participants.map(\.name) == ["A", "B", "C"])
        #expect(!diagram.messages.contains { $0.label == "d" })
    }

    @Test func mutualRecursionTerminates() {
        // A.ping -> B.pong -> A.ping ... must terminate via the visited guard.
        let art = artifact(types: [
            type("A", members: [method("ping", calls: [CallSite(receiverType: "B", methodName: "pong")])]),
            type("B", members: [method("pong", calls: [CallSite(receiverType: "A", methodName: "ping")])])
        ])

        let diagram = art.sequenceDiagram(entryPoint: ("A", "ping"), maxDepth: 50)

        // Terminates and revisits A as a participant without looping forever.
        #expect(diagram.participants.map(\.name) == ["A", "B"])
        #expect(diagram.messages.contains { $0.label == "pong" })
    }

    // MARK: - Interface resolution (typeMapping)

    @Test func typeMappingRedirectsAbstractReceiverToConcreteType() {
        // Service depends on a protocol; the body of the concrete impl is followed
        // only when the protocol is mapped to it.
        let art = artifact(types: [
            type("Service", members: [
                method("run", calls: [CallSite(receiverType: "RepositoryProtocol", methodName: "save")])
            ]),
            type("RepositoryProtocol", kind: .protocol, members: [method("save")]),
            type("SQLRepository", members: [
                method("save", calls: [CallSite(receiverType: "Database", methodName: "commit")])
            ]),
            type("Database", members: [method("commit")])
        ])

        // Without mapping: the protocol lifeline appears, but its body isn't followed.
        let unmapped = art.sequenceDiagram(entryPoint: ("Service", "run"))
        #expect(unmapped.participants.map(\.name) == ["Service", "RepositoryProtocol"])
        #expect(!unmapped.messages.contains { $0.label == "commit" })

        // With mapping: the lifeline becomes the concrete type and its body is traced.
        let mapped = art.sequenceDiagram(
            entryPoint: ("Service", "run"),
            typeMapping: ["RepositoryProtocol": "SQLRepository"]
        )
        #expect(mapped.participants.map(\.name) == ["Service", "SQLRepository", "Database"])
        #expect(mapped.messages.contains { $0.from == "Service" && $0.to == "SQLRepository" && $0.label == "save" })
        #expect(mapped.messages.contains { $0.label == "commit" })
        #expect(!mapped.participants.contains { $0.name == "RepositoryProtocol" })
    }

    // MARK: - Edge cases

    @Test func unknownEntryPointYieldsEmptyDiagram() {
        let art = artifact(types: [type("A", members: [method("a")])])

        let diagram = art.sequenceDiagram(entryPoint: ("Nope", "missing"))

        #expect(diagram.participants.isEmpty)
        #expect(diagram.messages.isEmpty)
        #expect(diagram.title == "Nope.missing()")
    }

    @Test func defaultTitleDerivesFromEntryPoint() {
        let art = artifact(types: [type("A", members: [method("a")])])
        let diagram = art.sequenceDiagram(entryPoint: ("A", "a"))
        #expect(diagram.title == "A.a()")
    }
}
