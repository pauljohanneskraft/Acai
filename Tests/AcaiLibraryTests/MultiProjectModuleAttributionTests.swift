import Foundation
import Testing
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// The shape the folder-of-projects case turns on: two Swift packages side by side, each declaring
/// a `Core` target. End-to-end through `AnalysisService.standard.analyzeProject`, so discovery,
/// the real parser and `ModuleMap` all have to agree on the project a file came from.
@Suite("Multi-project module attribution", .timeLimit(.minutes(1)))
struct MultiProjectModuleAttributionTests {

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("acai-multi-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// `app-ios` and `app-mac` each hold a `Core` target with a type of its own name, so a
    /// collapsed attribution would show one `Core` box with both types in it.
    private func writeTwoPackagesEachWithCore(in root: URL) throws {
        try write("app-ios/Package.swift", in: root, contents: "// swift-tools-version:5.9")
        try write("app-ios/Sources/Core/IOSCore.swift", in: root, contents: "public class IOSCore {}")
        try write("app-mac/Package.swift", in: root, contents: "// swift-tools-version:5.9")
        try write("app-mac/Sources/Core/MacCore.swift", in: root, contents: "public class MacCore {}")
    }

    @Test("two roots each declaring Core produce two distinct modules")
    func twoRootsProduceTwoDistinctModules() async throws {
        try await withTempDir { root in
            try writeTwoPackagesEachWithCore(in: root)

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
            let metrics = artifact.computeMetrics()

            #expect(Set(metrics.modules.map(\.name)) == ["app-ios/Core", "app-mac/Core"])
            #expect(Set(metrics.types.map(\.module)) == ["app-ios/Core", "app-mac/Core"])
        }
    }

    @Test("two roots each declaring Core produce two package boxes, one per project")
    func twoRootsProduceTwoPackageBoxes() async throws {
        try await withTempDir { root in
            try writeTwoPackagesEachWithCore(in: root)

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
            let diagram = PackageDiagramBuilder().build(from: artifact)

            #expect(diagram.nodes.count == 2)
            #expect(Set(diagram.nodes.compactMap(\.project)) == ["app-ios", "app-mac"])
            // The box inside a project reads as the module alone; the project labels the outer box.
            #expect(Set(diagram.nodes.map(\.moduleName)) == ["Core"])

            let dot = PackageDiagramDOTRenderer().render(diagram)
            #expect(dot.contains("label=\"app-ios\";"))
            #expect(dot.contains("label=\"app-mac\";"))
            #expect(dot.ranges(of: "subgraph cluster_project_").count == 2)
        }
    }

    @Test("two roots each declaring Core.Foo get ids scoped by the module ModuleMap reports")
    func sameTypeInSameNamedModulesOfTwoProjects() async throws {
        try await withTempDir { root in
            for project in ["app-ios", "app-mac"] {
                try write("\(project)/Package.swift", in: root, contents: "// swift-tools-version:5.9")
                try write("\(project)/Sources/Core/Foo.swift", in: root, contents: "public class Foo {}")
                try write(
                    "\(project)/Sources/Core/Bar.swift", in: root,
                    contents: "public class Bar { let foo: Foo; init(foo: Foo) { self.foo = foo } }")
            }

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
            let modules = ModuleMap(artifact: artifact)
            let types = artifact.flattened()

            #expect(Set(types.map(\.id))
                == ["app-ios/Core.Foo", "app-ios/Core.Bar", "app-mac/Core.Foo", "app-mac/Core.Bar"])
            for type in types {
                let module = modules.module(forFilePath: type.location?.filePath ?? "")
                #expect(type.id == "\(module).\(type.name)")
                #expect(type.module == module)
            }
            let edges = Set(
                artifact.relationships.filter { $0.kind == .composition }.map { "\($0.source)->\($0.target)" })
            #expect(edges == ["app-ios/Core.Bar->app-ios/Core.Foo", "app-mac/Core.Bar->app-mac/Core.Foo"])
            #expect(Set(artifact.computeMetrics().types.map(\.name)) == Set(types.map(\.id)))
        }
    }

    /// One root is the single-project case the issue pins: names stay exactly what the anchor
    /// derives, and nothing grows a project box.
    @Test("one root leaves module names unqualified and draws no project box")
    func oneRootIsUnchanged() async throws {
        try await withTempDir { root in
            try write("Package.swift", in: root, contents: "// swift-tools-version:5.9")
            try write("Sources/Core/A.swift", in: root, contents: "public class A {}")
            try write("Sources/UI/B.swift", in: root, contents: "public class B {}")

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
            let diagram = PackageDiagramBuilder().build(from: artifact)

            #expect(Set(artifact.computeMetrics().modules.map(\.name)) == ["Core", "UI"])
            #expect(diagram.nodes.allSatisfy { $0.project == nil })
            #expect(!PackageDiagramDOTRenderer().render(diagram).contains("subgraph cluster_project_"))
        }
    }
}
