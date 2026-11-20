import Testing
import Foundation
@testable import AcaiCore

private struct FixedArtifactParser: CodeParser {
    let artifact: CodeArtifact
    var language: CodeArtifact.SourceLanguage { CodeArtifact.SourceLanguage(rawValue: "fixed") }
    var fileExtensions: [String] { ["fixed"] }
    var configuration: LanguageConfiguration { .test }

    func parse(source: String, fileName: String) -> CodeArtifact { artifact }
}

@Suite("Core: Extension Resolution Scaling")
struct ExtensionResolutionScalingTests {

    private func type(
        _ name: String,
        kind: TypeKind = .struct,
        members: [Member] = [],
        nested: [TypeDeclaration] = [],
        extensionOf: String? = nil,
        file: String = "M/Sources/M/S.swift"
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name,
            kind: extensionOf == nil ? kind : .extension,
            accessLevel: .internal,
            members: members, nestedTypes: nested,
            extensionOf: extensionOf,
            location: SourceLocation(filePath: file, line: 1, column: 1)
        )
    }

    private func member(_ name: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal)
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    /// `typeCount` plain types named `T0…`, then `extensionCount` extensions spread over them.
    private func corpus(typeCount: Int, extensionCount: Int) -> CodeArtifact {
        var types = (0..<typeCount).map { type("T\($0)", members: [member("own\($0)")]) }
        types += (0..<extensionCount).map { index in
            type(
                "T\(index % typeCount)",
                members: [member("fromExtension\(index)")],
                extensionOf: "T\(index % typeCount)")
        }
        return artifact(types)
    }

    /// Analyses one file whose parse is `artifact`, so the counter reaches enrichment through `AnalysisService`.
    private func flattenPasses(analysing artifact: CodeArtifact) async throws -> Int {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acai-extension-scaling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "".write(to: root.appendingPathComponent("corpus.fixed"), atomically: true, encoding: .utf8)

        let counter = TypeFlattenCounter()
        let service = AnalysisService(parsers: [FixedArtifactParser(artifact: artifact)], typeFlattenCounter: counter)
        _ = try await service.analyzeProject(at: root, allowedLanguages: [])
        return counter.count
    }

    @Test func flatteningIsConstantWhateverTheExtensionCount() async throws {
        var passes: [Int] = []
        for extensionCount in [0, 1, 10, 1_000] {
            passes.append(try await flattenPasses(analysing: corpus(typeCount: 1_000, extensionCount: extensionCount)))
        }

        #expect(Set(passes).count == 1, "flattening passes varied with the extension count: \(passes)")
        #expect(passes[0] > 0 && passes[0] <= 8)
    }

    @Test func flatteningIsConstantWhateverTheTypeCount() async throws {
        let small = try await flattenPasses(analysing: corpus(typeCount: 10, extensionCount: 10))
        let large = try await flattenPasses(analysing: corpus(typeCount: 1_000, extensionCount: 10))

        #expect(small == large)
    }

    @Test func extensionMergesIntoExactlyOneOfTwoSameIDTypes() {
        let nestedTwin = type("Holder.Twin", members: [member("nestedOwn")])
        let holder = type("Holder", kind: .class, nested: [nestedTwin])
        let topLevelTwin = type("Holder.Twin", members: [member("topOwn")])
        let ext = type("Holder.Twin", members: [member("fromExtension")], extensionOf: "Holder.Twin")

        let resolved = artifact([holder, topLevelTwin, ext]).resolvingExtensions()

        let twins = resolved.flattened().filter { $0.id == "Holder.Twin" }
        #expect(twins.map { $0.members.map(\.name) } == [["nestedOwn", "fromExtension"], ["topOwn"]])
    }

    @Test func earlierRegisteredTypeWinsOverExtensionAddedNestedTypeWithTheSameID() {
        let outer = type("Outer", kind: .class)
        let later = type("Outer.Shared", members: [member("topOwn")])
        let addsNested = type(
            "Outer", nested: [type("Outer.Shared", members: [member("nestedOwn")])], extensionOf: "Outer")
        let extendsShared = type("Outer.Shared", members: [member("fromExtension")], extensionOf: "Outer.Shared")

        let resolved = artifact([outer, later, addsNested, extendsShared]).resolvingExtensions()

        let shared = resolved.flattened().filter { $0.id == "Outer.Shared" }
        #expect(shared.map { $0.members.map(\.name) } == [["nestedOwn"], ["topOwn", "fromExtension"]])
    }

    @Test func everyExtensionMergesIntoItsOwnTargetAtScale() {
        let resolved = corpus(typeCount: 1_000, extensionCount: 1_000).enriched()
        let byID = Dictionary(
            resolved.flattened().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        #expect(resolved.flattened().count == 1_000)
        #expect(!resolved.flattened().contains { $0.kind == .extension })
        for index in 0..<1_000 {
            let names = byID["T\(index)"]?.members.map(\.name) ?? []
            #expect(names.sorted() == ["fromExtension\(index)", "own\(index)"].sorted())
        }
    }

    @Test func extensionTargetsNestedTypeAddedByAnEarlierExtension() {
        let outer = type("Outer", kind: .class)
        let addsInner = type(
            "Outer", nested: [type("Outer.Inner", members: [member("fromFirst")])], extensionOf: "Outer")
        let extendsInner = type(
            "Outer.Inner", members: [member("fromSecond")], extensionOf: "Outer.Inner")

        let resolved = artifact([outer, addsInner, extendsInner]).enriched()

        let inner = resolved.flattened().first { $0.id == "Outer.Inner" }
        #expect(inner?.members.map(\.name).sorted() == ["fromFirst", "fromSecond"])
    }

    @Test func chainedNestedExtensionsAllResolve() {
        var types = [type("Root", kind: .class)]
        var path = "Root"
        for depth in 0..<5 {
            let nestedID = "\(path).N\(depth)"
            types.append(type(path, nested: [type(nestedID)], extensionOf: path))
            types.append(type(nestedID, members: [member("at\(depth)")], extensionOf: nestedID))
            path = nestedID
        }

        let resolved = artifact(types).enriched()

        let deepest = resolved.flattened().first { $0.id == path }
        #expect(deepest?.members.map(\.name) == ["at4"])
        #expect(resolved.flattened().count == 6)
    }

    @Test func genericArgumentsAreStrippedFromTheTargetName() {
        let box = type("Box", kind: .struct)
        let ext = type("Box<T>", members: [member("mapped")], extensionOf: "Box<T>")

        let resolved = artifact([box, ext]).enriched()

        #expect(resolved.flattened().first { $0.id == "Box" }?.members.map(\.name) == ["mapped"])
    }
}
