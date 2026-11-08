import Testing
import AcaiCore
import AcaiDiagram
import AcaiTestSupport
import AcaiAppModel

@Suite("State Config Model")
struct StateConfigModelTests {

    /// `Loader` holds an enum-typed `state`, a `String` `label`, an unrelated `Data` `payload` and a
    /// computed property; `Outer.Inner` proves nested types are reachable. One global too.
    private func artifact() -> CodeArtifact {
        let loader = TypeDeclaration(
            id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class, accessLevel: .public,
            members: [
                Member(name: "payload", kind: .property, accessLevel: .internal,
                       type: TypeReference(name: "Data")),
                Member(name: "label", kind: .property, accessLevel: .internal,
                       type: TypeReference(name: "String")),
                Member(name: "state", kind: .property, accessLevel: .internal,
                       type: TypeReference(name: "Phase")),
                Member(name: "isBusy", kind: .property, accessLevel: .internal,
                       type: TypeReference(name: "Bool"), isComputed: true)
            ]
        )
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .class, accessLevel: .public,
            nestedTypes: [
                TypeDeclaration(
                    id: "Outer.Inner", name: "Inner", qualifiedName: "Outer.Inner", kind: .struct,
                    accessLevel: .public,
                    members: [Member(name: "flag", kind: .property, accessLevel: .internal,
                                     type: TypeReference(name: "Bool"))]
                )
            ]
        )
        let phase = TypeDeclaration(
            id: "Phase", name: "Phase", qualifiedName: "Phase", kind: .enum, accessLevel: .public)
        return CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: ["Loader.swift"]),
            types: [loader, outer, phase],
            globalVariables: [Member(name: "appMode", kind: .property, accessLevel: .internal,
                                     type: TypeReference(name: "Int"))]
        )
    }

    @Test func itStartsWithNoScopeAndCannotCreate() {
        let model = StateConfigModel(artifact: artifact())
        #expect(model.scope == nil)
        #expect(model.variableName.isEmpty)
        #expect(!model.canCreate)
        #expect(model.maxStates == 20)
        #expect(model.variableNames.isEmpty)
    }

    @Test func anExistingConfigurationPreFillsTheScopeAndVariable() {
        let model = StateConfigModel(
            artifact: artifact(),
            initial: StateDiagramConfiguration(typeName: "Loader", variableName: "state", maxStates: 45)
        )
        #expect(model.scope == .type("Loader"))
        #expect(model.variableName == "state")
        #expect(model.maxStates == 45)
        #expect(model.canCreate)
    }

    /// A configuration with no `typeName` is the globals scope, not "nothing selected".
    @Test func aGlobalConfigurationRestoresTheGlobalsScope() {
        let model = StateConfigModel(
            artifact: artifact(),
            initial: StateDiagramConfiguration(typeName: nil, variableName: "appMode")
        )
        #expect(model.scope == .globals)
        #expect(model.canCreate)
    }

    @Test func onlyTypesWithStoredPropertiesAreOfferedAndNestedOnesAreQualified() {
        let model = StateConfigModel(artifact: artifact())
        // `Outer` has only a nested type, `Phase` has no members at all — neither is offered.
        #expect(model.typeIDsWithStoredProperties == ["Loader", "Outer.Inner"])
        #expect(model.hasGlobalVariables)
    }

    /// Enum/bool/int/string-typed properties come first; a computed property is never a stored state.
    @Test func plausibleStateHoldersAreListedFirstAndComputedPropertiesNeverAppear() {
        var model = StateConfigModel(artifact: artifact())
        model.selectScope(.type("Loader"))
        #expect(model.variableNames == ["label", "state", "payload"])
    }

    @Test func pickingAScopeTakesTheVariableSelectionWithIt() {
        var model = StateConfigModel(artifact: artifact())

        model.selectScope(.type("Loader"))
        #expect(model.variableName == "label")

        model.variableName = "state"
        model.selectScope(.type("Loader"))
        #expect(model.variableName == "state")

        // `state` doesn't exist in the globals scope, so it can't survive the change.
        model.selectScope(.globals)
        #expect(model.variableName == "appMode")

        model.selectScope(nil)
        #expect(model.variableNames.isEmpty)
        #expect(model.variableName.isEmpty)
        #expect(!model.canCreate)
    }

    @Test func aNestedTypesScopeResolvesByQualifiedName() {
        var model = StateConfigModel(artifact: artifact())
        model.selectScope(.type("Outer.Inner"))
        #expect(model.variableNames == ["flag"])
    }

    @Test func theTypeScopeProducesATypedConfigurationAndGlobalsProduceANilOne() {
        var model = StateConfigModel(artifact: artifact())
        model.selectScope(.type("Loader"))
        model.variableName = "state"
        model.maxStates = 35
        #expect(model.configuration == StateDiagramConfiguration(
            typeName: "Loader", variableName: "state", maxStates: 35))

        model.selectScope(.globals)
        #expect(model.configuration.typeName == nil)
        #expect(model.configuration.variableName == "appMode")
    }

    /// Module-scoped ids tag each option, so the configuration names the exact type; the label is its plain name.
    @Test func aModuleScopedTypeIsPickedByItsIDAndShownByItsName() {
        let scoped = artifact().scopingTypeIDs(modules: ModuleMap(roots: [], filePaths: []))
        var model = StateConfigModel(artifact: scoped)
        let ids = model.typeIDsWithStoredProperties
        #expect(ids.allSatisfy { $0.hasPrefix("root.") })
        #expect(ids.map(model.typeDisplayNames.name(forID:)) == ["Loader", "Outer.Inner"])

        model.selectScope(.type(ids[0]))
        model.variableName = "state"
        #expect(model.configuration.typeName == ids[0])
    }

    @Test func aCodebaseWithoutGlobalsDoesNotOfferTheGlobalsScope() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: ["A.swift"]))
        #expect(!StateConfigModel(artifact: artifact).hasGlobalVariables)
    }

    /// The seam is injected per instance, so this counts only this model's own passes. The picker
    /// lists are read on every render and `selectScope` re-reads the variable list, so a lookup
    /// derived per access rather than per model would show up here as more than one walk.
    @Test func theLookupsWalkTheAnalysisOncePerModelLifetime() {
        let walks = Locked(0)
        var model = StateConfigModel(
            artifact: artifact(),
            walkObserver: AnalysisWalkObserver { walks.withValue { $0 += 1 } }
        )
        #expect(walks.value == 1)

        for _ in 0..<5 {
            _ = model.typeDisplayNames
            _ = model.typeIDsWithStoredProperties
            _ = model.variableNames
            _ = model.hasGlobalVariables
        }
        model.selectScope(.type("Loader"))
        model.selectScope(.globals)
        model.selectScope(nil)
        _ = model.variableNames

        #expect(walks.value == 1)
    }

    @Test func twoModelsEachCountTheirOwnWalk() {
        let first = Locked(0)
        let second = Locked(0)
        _ = StateConfigModel(
            artifact: artifact(), walkObserver: AnalysisWalkObserver { first.withValue { $0 += 1 } }
        )
        _ = StateConfigModel(
            artifact: artifact(), walkObserver: AnalysisWalkObserver { second.withValue { $0 += 1 } }
        )
        #expect(first.value == 1)
        #expect(second.value == 1)
    }
}
