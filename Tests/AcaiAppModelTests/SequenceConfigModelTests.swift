import Testing
import AcaiCore
import AcaiDiagram
import AcaiAppModel

@Suite("Sequence Config Model")
struct SequenceConfigModelTests {

    /// `Service.run` calls `Store.save`; `Store` is a protocol with `DiskStore` conforming, so a
    /// trace from `Service.run` reaches one resolvable abstraction.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: ["Service.swift"]),
            types: [
                TypeDeclaration(
                    id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .type("Store"), methodName: "save")
                        ]),
                        Member(name: "reset", kind: .method, accessLevel: .internal)
                    ]
                ),
                TypeDeclaration(
                    id: "Store", name: "Store", qualifiedName: "Store", kind: .protocol,
                    accessLevel: .public,
                    members: [Member(name: "save", kind: .method, accessLevel: .internal)]
                ),
                TypeDeclaration(
                    id: "DiskStore", name: "DiskStore", qualifiedName: "DiskStore", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "save", kind: .method, accessLevel: .internal)]
                )
            ],
            relationships: [Relationship(kind: .conformance, source: "DiskStore", target: "Store")]
        )
    }

    /// No abstraction anywhere, so there is nothing to ask about after the entry point.
    private func flatArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: ["Solo.swift"]),
            types: [
                TypeDeclaration(
                    id: "Solo", name: "Solo", qualifiedName: "Solo", kind: .class, accessLevel: .public,
                    members: [Member(name: "go", kind: .method, accessLevel: .internal)]
                )
            ]
        )
    }

    @Test func itStartsOnTheEntryPointStepAndCannotAdvanceWithoutAMethod() {
        let model = SequenceConfigModel(artifact: artifact())
        #expect(model.step == .entryPoint)
        #expect(model.entryTypeName.isEmpty)
        #expect(model.entryMethodName.isEmpty)
        #expect(!model.canAdvance)
        #expect(model.maxDepth == 5)
    }

    @Test func anExistingConfigurationPreFillsEveryField() {
        let model = SequenceConfigModel(
            artifact: artifact(),
            initial: SequenceDiagramConfiguration(
                entryTypeName: "Service", entryMethodName: "run", maxDepth: 9,
                typeMapping: ["Store": "DiskStore"])
        )
        #expect(model.entryTypeName == "Service")
        #expect(model.entryMethodName == "run")
        #expect(model.maxDepth == 9)
        #expect(model.canAdvance)
    }

    @Test func onlyTypesWithMethodsAreOfferedAsAScope() {
        let model = SequenceConfigModel(artifact: artifact())
        #expect(model.callableTypeNames == ["DiskStore", "Service", "Store"])
    }

    @Test func pickingAScopeKeepsAMethodThatExistsThereAndReplacesOneThatDoesNot() {
        var model = SequenceConfigModel(artifact: artifact())

        model.selectEntryType("Service")
        // No method was selected, so the new scope's first one is taken.
        #expect(model.entryMethodName == "reset")

        model.entryMethodName = "run"
        model.selectEntryType("Service")
        #expect(model.entryMethodName == "run")

        // `run` doesn't exist on `Store`, so it can't survive the scope change.
        model.selectEntryType("Store")
        #expect(model.entryMethodName == "save")
    }

    @Test func aScopeWithNoMethodsLeavesTheMethodSelectionEmpty() {
        var model = SequenceConfigModel(artifact: artifact())
        model.entryMethodName = "run"
        model.selectEntryType("Unknown")
        #expect(model.methodNames.isEmpty)
        #expect(model.entryMethodName.isEmpty)
    }

    @Test func advancingFromATraceThatReachesAnAbstractionAsksToResolveIt() throws {
        var model = SequenceConfigModel(artifact: artifact())
        model.selectEntryType("Service")
        model.entryMethodName = "run"

        #expect(model.advance() == .resolveInterfaces)
        #expect(model.step == .resolveInterfaces)
        let mapping = try #require(model.mappings.first)
        #expect(model.mappings.count == 1)
        #expect(mapping.protocolName == "Store")
        #expect(mapping.candidates == ["DiskStore"])
        #expect(mapping.selection == nil)
    }

    @Test func advancingWithNothingToResolveFinishesWithTheConfiguration() {
        var model = SequenceConfigModel(artifact: flatArtifact())
        model.selectEntryType("Solo")
        model.entryMethodName = "go"
        model.maxDepth = 3

        #expect(model.advance() == .finished(SequenceDiagramConfiguration(
            entryTypeName: "Solo", entryMethodName: "go", maxDepth: 3, typeMapping: [:])))
        // No step to show, so the flow stays where it was rather than presenting an empty form.
        #expect(model.step == .entryPoint)
    }

    @Test func aResolvedAbstractionReachesTheConfigurationAndLeavingItAbstractDoesNot() {
        var model = SequenceConfigModel(artifact: artifact())
        model.selectEntryType("Service")
        model.entryMethodName = "run"
        _ = model.advance()

        model.select("DiskStore", forAbstractionNamed: "Store")
        #expect(model.configuration.typeMapping == ["Store": "DiskStore"])

        model.select(nil, forAbstractionNamed: "Store")
        #expect(model.configuration.typeMapping.isEmpty)
    }

    @Test func anExistingMappingPreSelectsItsConcreteType() throws {
        var model = SequenceConfigModel(
            artifact: artifact(),
            initial: SequenceDiagramConfiguration(
                entryTypeName: "Service", entryMethodName: "run", typeMapping: ["Store": "DiskStore"])
        )
        _ = model.advance()
        #expect(try #require(model.mappings.first).selection == "DiskStore")
        #expect(model.configuration.typeMapping == ["Store": "DiskStore"])
    }

    @Test func goingBackReturnsToTheEntryPointStepWithoutLosingTheMappings() {
        var model = SequenceConfigModel(artifact: artifact())
        model.selectEntryType("Service")
        model.entryMethodName = "run"
        _ = model.advance()
        model.select("DiskStore", forAbstractionNamed: "Store")

        model.back()
        #expect(model.step == .entryPoint)
        #expect(model.mappings.first?.selection == "DiskStore")
    }

    @Test func selectingAnAbstractionThatIsNotOfferedChangesNothing() {
        var model = SequenceConfigModel(artifact: artifact())
        model.selectEntryType("Service")
        model.entryMethodName = "run"
        _ = model.advance()

        model.select("DiskStore", forAbstractionNamed: "NoSuchProtocol")
        #expect(model.mappings.count == 1)
        #expect(model.configuration.typeMapping.isEmpty)
    }

    @Test func theEmptyScopeOffersTopLevelFunctions() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: ["main.swift"]),
            freestandingFunctions: [Member(name: "main", kind: .method, accessLevel: .internal)]
        )
        let model = SequenceConfigModel(artifact: artifact)
        #expect(model.entryTypeName.isEmpty)
        #expect(model.freeFunctionNames == ["main"])
        #expect(model.methodNames == ["main"])
    }
}
