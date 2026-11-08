import Testing
import AcaiCore
import AcaiDiagram
import AcaiTestSupport
import AcaiAppModel

@Suite("Call Graph Config Model")
struct CallGraphConfigModelTests {

    /// `Service` and `Helper` declare methods and so can be scoped to; `Record` holds only
    /// properties and cannot. `Service` appears twice to prove the lists are uniqued, and the three
    /// file paths sit in two different module directories.
    private func artifact() -> CodeArtifact {
        let method = Member(name: "run", kind: .method, accessLevel: .public)
        let service = TypeDeclaration(
            id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
            accessLevel: .public, members: [method],
            location: SourceLocation(filePath: "Sources/Core/Service.swift", line: 1, column: 1)
        )
        let helper = TypeDeclaration(
            id: "Helper", name: "Helper", qualifiedName: "Helper", kind: .struct,
            accessLevel: .public, members: [method],
            location: SourceLocation(filePath: "Sources/Support/Helper.swift", line: 1, column: 1)
        )
        let record = TypeDeclaration(
            id: "Record", name: "Record", qualifiedName: "Record", kind: .struct,
            accessLevel: .public,
            members: [Member(name: "id", kind: .property, accessLevel: .public)],
            location: SourceLocation(filePath: "Sources/Core/Record.swift", line: 1, column: 1)
        )
        return CodeArtifact(
            metadata: .init(
                sourceLanguage: .init(rawValue: "swift"),
                filePaths: ["Sources/Core/Service.swift", "Sources/Support/Helper.swift",
                            "Sources/Core/Record.swift"]
            ),
            types: [service, helper, record, service]
        )
    }

    @Test func itStartsAtTheScopeItWasGiven() {
        #expect(CallGraphConfigModel(artifact: artifact()).scope == .wholeCodebase)
        #expect(CallGraphConfigModel(artifact: artifact(), initial: .type("Service")).scope == .type("Service"))
    }

    @Test func onlyTypesWithMethodsCanBeScopedTo() {
        #expect(CallGraphConfigModel(artifact: artifact()).typeNames == ["Helper", "Service"])
    }

    @Test func theModuleListIsTheOneTheModuleMapDerives() {
        let artifact = artifact()
        let modules = ModuleMap(artifact: artifact)
        let expected = artifact.types
            .map { modules.module(forFilePath: $0.location?.filePath ?? "") }
            .uniqued()
            .sorted()
        #expect(CallGraphConfigModel(artifact: artifact).moduleNames == expected)
    }

    @Test func theListsAreUniquedAndSorted() {
        let model = CallGraphConfigModel(artifact: artifact())
        #expect(model.typeNames == model.typeNames.uniqued().sorted())
        #expect(model.moduleNames == model.moduleNames.uniqued().sorted())
    }

    @Test func anEmptyAnalysisOffersNoTypesAndNoModules() {
        let model = CallGraphConfigModel(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .init(rawValue: "swift"), filePaths: []))
        )
        #expect(model.typeNames.isEmpty)
        #expect(model.moduleNames.isEmpty)
    }

    /// The seam is injected per instance, so this counts only this model's own passes.
    @Test func theLookupsWalkTheAnalysisOncePerModelLifetime() {
        let walks = Locked(0)
        var model = CallGraphConfigModel(
            artifact: artifact(),
            walkObserver: AnalysisWalkObserver { walks.withValue { $0 += 1 } }
        )
        #expect(walks.value == 1)

        for _ in 0..<5 {
            _ = model.typeNames
            _ = model.moduleNames
        }
        model.scope = .type("Helper")
        _ = model.typeNames

        #expect(walks.value == 1)
    }

    @Test func twoModelsEachCountTheirOwnWalk() {
        let first = Locked(0)
        let second = Locked(0)
        _ = CallGraphConfigModel(
            artifact: artifact(), walkObserver: AnalysisWalkObserver { first.withValue { $0 += 1 } }
        )
        _ = CallGraphConfigModel(
            artifact: artifact(), walkObserver: AnalysisWalkObserver { second.withValue { $0 += 1 } }
        )
        #expect(first.value == 1)
        #expect(second.value == 1)
    }
}
