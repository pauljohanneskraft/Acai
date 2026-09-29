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
                .plugin(name: "Lint", capability: .buildTool()),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core", "Tool", "CoreTests", "Macros", "Lint"])
        #expect(parsed.targets.map(\.kind) == [.regular, .regular, .test, .regular, .plugin])
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

    /// Neither declares sources of its own, so skipping them is not a reason to distrust the rest.
    @Test func skipsBinaryAndSystemTargetsWithoutGivingUp() {
        let parsed = manifest("""

                .binaryTarget(name: "Prebuilt", path: "Prebuilt.xcframework"),
                .systemLibrary(name: "CZlib"),
                .target(name: "Core"),
        """)
        #expect(parsed.incompleteReason == nil)
        #expect(parsed.targets.map(\.name) == ["Core"])
    }

    // MARK: - Refusing a Manifest It Cannot Fully Read

    @Test func computedTargetListIsIncomplete() {
        let parsed = SwiftPackageManifest(source: """
        let package = Package(name: "Demo", targets: [.target(name: "Core")] + extraTargets)
        """)
        #expect(parsed.incompleteReason != nil)
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
