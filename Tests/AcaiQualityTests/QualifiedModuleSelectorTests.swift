import Testing
import AcaiCore
@testable import AcaiQuality

/// With several project roots a module name carries its project, so a rules file can address
/// `web/api` distinctly from `app-ios/api` — the point of qualifying it at all.
@Suite("Qualified module selectors")
struct QualifiedModuleSelectorTests {

    private func artifact() -> CodeArtifact {
        let paths = [
            "app-ios/Sources/api/IOSAPI.swift",
            "app-ios/Sources/ui/IOSUI.swift",
            "web/packages/api/WebAPI.ts",
            "web/packages/ui/WebUI.ts"
        ]
        var metadata = CodeArtifact.Metadata(sourceLanguage: .swift)
        metadata.filePaths = paths
        metadata.discoveredRoots = [
            CodeArtifact.DiscoveredRoot(path: "app-ios", detector: "Fake", languages: [.swift]),
            CodeArtifact.DiscoveredRoot(path: "web", detector: "Fake", languages: [.swift])
        ]
        let types = paths.map { path in
            let name = path.split(separator: "/").last.map { $0.split(separator: ".").first.map(String.init) ?? "" }
            return TypeDeclaration(
                id: path, name: name ?? "", qualifiedName: name ?? "", kind: .class, accessLevel: .public,
                location: SourceLocation(filePath: path, line: 1, column: 1))
        }
        return CodeArtifact(metadata: metadata, types: types)
    }

    private func graph() -> GraphView {
        GraphView(
            artifact: artifact(),
            languageResolver: LanguageConfigurationResolver(single: .test))
    }

    @Test func everyModuleNameCarriesItsProject() {
        #expect(graph().moduleNames == ["app-ios/api", "app-ios/ui", "web/api", "web/ui"])
        #expect(graph().projectNames == ["app-ios", "web"])
    }

    @Test func aSelectorAddressesOneProjectsModule() {
        let selector = Selector(module: "web/api")
        #expect(graph().moduleNames.filter(selector.matchesModule(named:)) == ["web/api"])
    }

    @Test func aProjectWideGlobKeepsTheOtherProjectOut() {
        let selector = Selector(module: "web/*")
        #expect(graph().moduleNames.filter(selector.matchesModule(named:)) == ["web/api", "web/ui"])
    }

    /// The bare name is deliberately no longer enough: it is exactly the ambiguity the qualification
    /// exists to remove.
    @Test func theBareModuleNameNoLongerMatchesEitherProject() {
        let selector = Selector(module: "api")
        #expect(graph().moduleNames.filter(selector.matchesModule(named:)).isEmpty)
    }

    @Test func aSelectorWithNoModuleStillMatchesEveryModule() {
        #expect(graph().moduleNames.allSatisfy(Selector().matchesModule(named:)))
    }
}
