import Foundation
import Testing
@testable import AcaiSwift

/// Reading a `Package.swift`'s declared target layout, and refusing to half-read one that computes
/// any of it.
@Suite("Swift package manifest", .timeLimit(.minutes(1)))
struct SwiftPackageManifestTests {

    private func manifest(_ targets: String) -> SwiftPackageManifest {
        SwiftPackageManifest(source: """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Demo",
            targets: [\(targets)]
        )
        """)
    }

    // MARK: - Reading Targets

    @Test func readsNameKindAndDefaultPath() {
        let parsed = manifest("""

                .target(name: "Core"),
                .executableTarget(name: "Tool"),
                .testTarget(name: "CoreTests"),
                .macro(name: "Macros"),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core", "Tool", "CoreTests", "Macros"])
        #expect(parsed.targets.map(\.kind) == [.regular, .regular, .test, .regular])
        #expect(parsed.targets.allSatisfy { $0.path == nil && $0.exclude.isEmpty && $0.sources == nil })
    }

    @Test func readsPathExcludeAndSources() {
        let parsed = manifest("""

                .target(name: "Core", path: "Lib/Core", exclude: ["Fixtures", "Notes.md"]),
                .target(name: "Narrow", sources: ["Public"]),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.first?.path == "Lib/Core")
        #expect(parsed.targets.first?.exclude == ["Fixtures", "Notes.md"])
        #expect(parsed.targets.last?.sources == ["Public"])
    }

    /// None of the three contributes Swift source of the package's own — a plugin is a build tool
    /// rather than product code — so skipping them is not a reason to distrust the rest.
    @Test func skipsBinarySystemAndPluginTargetsWithoutGivingUp() {
        let parsed = manifest("""

                .binaryTarget(name: "Prebuilt", path: "Prebuilt.xcframework"),
                .systemLibrary(name: "CZlib"),
                .plugin(name: "Lint", capability: .buildTool()),
                .target(name: "Core"),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core"])
    }

    // MARK: - Resources

    @Test func readsResourceRulePathsAsPathsToSkip() {
        let parsed = manifest("""

                .testTarget(name: "CoreTests", resources: [
                    .copy("Fixtures"),
                    .process("Assets"),
                    .embedInCode("golden.json"),
                ]),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.first?.resources == ["Fixtures", "Assets", "golden.json"])
    }

    @Test func aComputedResourceListIsIncomplete() {
        #expect(manifest(#".target(name: "Core", resources: fixtureRules)"#).incompleteReason != nil)
        #expect(manifest(#".target(name: "Core", resources: [.copy(name)])"#).incompleteReason != nil)
        #expect(manifest(#".target(name: "Core", resources: [makeRule()])"#).incompleteReason != nil)
    }

    // MARK: - Following a Concatenated or Named Target List

    @Test func readsTargetsConcatenatedWithALiteralArray() {
        let parsed = SwiftPackageManifest(source: """
        let package = Package(
            name: "Demo",
            targets: [.target(name: "Core")] + [.target(name: "UI"), .testTarget(name: "CoreTests")]
        )
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core", "UI", "CoreTests"])
    }

    @Test func followsALetBoundTargetList() {
        let parsed = SwiftPackageManifest(source: """
        let optionalTargets: [Target] = [.target(name: "UI")]
        let package = Package(
            name: "Demo",
            targets: [.target(name: "Core")] + optionalTargets
        )
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core", "UI"])
    }

    /// The whole `targets:` argument may be a name, and a name may resolve to another concatenation.
    @Test func followsANamedTargetListThroughSeveralBindings() {
        let parsed = SwiftPackageManifest(source: """
        let core: [Target] = [.target(name: "Core")]
        let extras: [Target] = [.target(name: "UI")]
        let all = core + extras
        let package = Package(name: "Demo", targets: all)
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core", "UI"])
    }

    @Test func aVarBoundTargetListIsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        var extras: [Target] = [.target(name: "UI")]
        let package = Package(name: "Demo", targets: [.target(name: "Core")] + extras)
        """)
        #expect(parsed.incompleteReason != nil)
        #expect(parsed.targets.isEmpty)
    }

    @Test func aCyclicBindingTerminatesAsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        let a = b
        let b = a
        let package = Package(name: "Demo", targets: a)
        """)
        #expect(parsed.incompleteReason != nil)
    }

    @Test func anOperatorOtherThanPlusIsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        let extras: [Target] = [.target(name: "UI")]
        let package = Package(name: "Demo", targets: [.target(name: "Core")] ?? extras)
        """)
        #expect(parsed.incompleteReason != nil)
    }

    // MARK: - Refusing a Manifest It Cannot Fully Read

    /// Nothing in the file binds `extraTargets`, so there is no layout to read.
    @Test func computedTargetListIsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        let package = Package(name: "Demo", targets: [.target(name: "Core")] + extraTargets)
        """)
        #expect(parsed.incompleteReason != nil)
        #expect(parsed.targets.isEmpty)
    }

    @Test func targetsBuiltByAHelperAreIncomplete() {
        let parsed = manifest("""

                .target(name: "Core"),
                makeTarget("Extra"),
        """)
        #expect(parsed.incompleteReason != nil)
    }

    @Test func computedArgumentsAreIncomplete() {
        #expect(manifest(#".target(name: "Core", path: root + "/Core")"#).incompleteReason != nil)
        #expect(manifest(#".target(name: "Core", path: "\(root)/Core")"#).incompleteReason != nil)
        #expect(manifest(#".target(name: "Core", exclude: fixtures)"#).incompleteReason != nil)
        #expect(manifest(#".target(name: "Core", sources: ["A", dynamic])"#).incompleteReason != nil)
        #expect(manifest(".target(name: nameVariable)").incompleteReason != nil)
    }

    @Test func conditionalCompilationAroundTargetsIsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        var targets: [Target] = [.target(name: "Core")]
        #if canImport(SwiftUI)
        targets.append(.target(name: "UI"))
        #endif
        let package = Package(name: "Demo", targets: targets)
        """)
        #expect(parsed.incompleteReason != nil)
        #expect(parsed.targets.isEmpty)
    }

    @Test(arguments: [
        "package.targets.append(.target(name: \"Extra\"))",
        "package.targets += [.target(name: \"Extra\")]",
        "package.targets[0].path = \"Elsewhere\"",
        "for target in package.targets { target.exclude.append(\"Fixtures\") }"
    ])
    func changingTheLayoutAfterTheInitializerIsIncomplete(statement: String) {
        let parsed = SwiftPackageManifest(source: """
        let package = Package(name: "Demo", targets: [.target(name: "Core")])
        \(statement)
        """)
        #expect(parsed.incompleteReason != nil)
    }

    @Test func settingsAppliedAfterTheInitializerLeaveTheLayoutReadable() {
        let parsed = SwiftPackageManifest(source: """
        let package = Package(name: "Demo", targets: [.target(name: "Core")])
        for target in package.targets { target.swiftSettings = [.enableUpcomingFeature("ExistentialAny")] }
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core"])
    }

    @Test func aManifestWithoutAPackageInitializerIsIncomplete() {
        #expect(SwiftPackageManifest(source: "// nothing here").incompleteReason != nil)
        #expect(SwiftPackageManifest(source: "").incompleteReason != nil)
    }

    /// A `.target(name:)` inside a target's own `dependencies:` must not be mistaken for a target.
    @Test func targetDependenciesAreNotTargets() {
        let parsed = manifest(#".target(name: "App", dependencies: [.target(name: "Core")])"#)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["App"])
    }
}
