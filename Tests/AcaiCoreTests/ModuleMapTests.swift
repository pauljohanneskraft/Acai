import Testing

@testable import AcaiCore

/// The map decides *whether* a module name carries its project: one root keeps today's names, more
/// than one qualifies them so two projects' `Core` targets stay apart.
@Suite("Module map")
struct ModuleMapTests {

    private let singleRootPaths = ["Sources/Core/A.swift", "Sources/UI/B.swift", "README.md"]

    private let twoRootPaths = [
        "app-ios/Sources/Core/A.swift",
        "app-ios/Sources/UI/B.swift",
        "web/packages/core/src/index.ts",
        "web/src/app.ts"
    ]

    @Test func oneRootNamesModulesExactlyAsTheResolverDoes() {
        let map = ModuleMap(roots: ["."], filePaths: singleRootPaths)
        #expect(!map.isRootQualified)
        for path in singleRootPaths {
            #expect(map.module(forFilePath: path) == ModuleResolver.standard.productName(forFilePath: path))
        }
        #expect(map.project(ofModule: "Core") == nil)
    }

    @Test func noRootsAtAllAlsoLeavesNamesUnqualified() {
        let map = ModuleMap(roots: [], filePaths: singleRootPaths)
        #expect(!map.isRootQualified)
        #expect(map.module(forFilePath: "Sources/Core/A.swift") == "Core")
    }

    @Test func twoRootsQualifyEveryModuleWithItsProject() {
        let map = ModuleMap(roots: ["app-ios", "web"], filePaths: twoRootPaths)
        #expect(map.isRootQualified)
        #expect(map.module(forFilePath: "app-ios/Sources/Core/A.swift") == "app-ios/Core")
        #expect(map.module(forFilePath: "app-ios/Sources/UI/B.swift") == "app-ios/UI")
        #expect(map.module(forFilePath: "web/packages/core/src/index.ts") == "web/core")
        // `src` at the root's head is a single-module project, so the module is the project.
        #expect(map.module(forFilePath: "web/src/app.ts") == "web")
    }

    @Test func twoProjectsEachDeclaringCoreStayDistinct() {
        let paths = ["app-ios/Sources/Core/A.swift", "web/packages/Core/index.ts"]
        let map = ModuleMap(roots: ["app-ios", "web"], filePaths: paths)
        #expect(Set(paths.map(map.module(forFilePath:))) == ["app-ios/Core", "web/Core"])
        #expect(map.project(ofModule: "app-ios/Core") == "app-ios")
        #expect(map.project(ofModule: "web/Core") == "web")
    }

    /// The deepest root wins, so a package nested inside another project is its own project rather
    /// than a target of its ancestor.
    @Test func aNestedRootClaimsItsOwnFiles() {
        let map = ModuleMap(
            roots: [".", "vendor/sdk"],
            filePaths: ["Sources/App/A.swift", "vendor/sdk/Sources/Net/B.swift"])
        #expect(map.module(forFilePath: "Sources/App/A.swift") == "root/App")
        #expect(map.module(forFilePath: "vendor/sdk/Sources/Net/B.swift") == "sdk/Net")
    }

    /// A location that never reached `metadata.filePaths` is resolved on demand, not missed.
    @Test func aPathTheMapWasNotBuiltWithStillResolves() {
        let map = ModuleMap(roots: ["app-ios", "web"], filePaths: [])
        #expect(map.module(forFilePath: "web/packages/core/src/index.ts") == "web/core")
    }

    @Test func artifactMetadataDrivesTheMap() {
        var metadata = CodeArtifact.Metadata(sourceLanguage: .init(rawValue: "swift"))
        metadata.filePaths = ["one/Sources/Core/A.swift", "two/Sources/Core/B.swift"]
        metadata.discoveredRoots = [
            CodeArtifact.DiscoveredRoot(path: "one", detector: "Fake", languages: []),
            CodeArtifact.DiscoveredRoot(path: "two", detector: "Fake", languages: [])
        ]
        let map = ModuleMap(artifact: CodeArtifact(metadata: metadata))
        #expect(map.module(forFilePath: "one/Sources/Core/A.swift") == "one/Core")
        #expect(map.module(forFilePath: "two/Sources/Core/B.swift") == "two/Core")
    }

    @Test func typeModulesAreKeyedByID() {
        let map = ModuleMap(roots: ["one", "two"], filePaths: [])
        let types = ["one/Sources/Core/A.swift", "two/Sources/Core/B.swift"].map { path in
            TypeDeclaration(
                id: path, name: "T", qualifiedName: "T", kind: .class, accessLevel: .internal,
                location: SourceLocation(filePath: path, line: 1, column: 1))
        }
        let byID = map.modules(ofTypes: types)
        #expect(byID[types[0].id] == "one/Core")
        #expect(byID[types[1].id] == "two/Core")
    }
}
