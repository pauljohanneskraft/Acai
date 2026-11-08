import Testing
import Foundation
@testable import AcaiCore

/// Extension resolution used to flatten every type again for each extension, so it cost
/// `O(extensions × types)`. These hold the flattening count flat as the extension count grows, and
/// pin the behaviour that a one-pass index has to keep: the lookups stay current as extensions merge.
@Suite("Core: Extension Resolution Scaling")
struct ExtensionResolutionScalingTests {

    private func type(
        _ name: String,
        kind: TypeKind = .struct,
        members: [Member] = [],
        nested: [TypeDeclaration] = [],
        extensionOf: String? = nil,
        module: String? = nil,
        file: String = "M/Sources/M/S.swift"
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name,
            kind: extensionOf == nil ? kind : .extension,
            accessLevel: .internal,
            members: members, nestedTypes: nested,
            extensionOf: extensionOf,
            module: module,
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

    private func enriching(_ artifact: CodeArtifact, counting counter: TypeFlattenCounter) -> CodeArtifact {
        artifact.enriched(using: LanguageConfigurationResolver(single: .test), counting: counter)
    }

    /// The regression guard: whatever the extension count, one `enriched()` flattens the tree the
    /// same number of times. Equality across the counts is the assertion that matters — a
    /// per-extension flatten would make the 1,000-extension run cost about 1,000 passes more than
    /// the 10-extension one. The ceiling catches the same regression if a pass is ever added.
    @Test func flatteningIsConstantWhateverTheExtensionCount() {
        let counts = [0, 1, 10, 1_000]
        let passes = counts.map { extensionCount -> Int in
            let counter = TypeFlattenCounter()
            _ = enriching(corpus(typeCount: 1_000, extensionCount: extensionCount), counting: counter)
            return counter.count
        }

        #expect(Set(passes).count == 1, "flattening passes varied with the extension count: \(passes)")
        #expect(passes[0] <= 8)
    }

    /// Flattening must not scale with the type count either: the count is per pass, not per type.
    @Test func flatteningIsConstantWhateverTheTypeCount() {
        let small = TypeFlattenCounter()
        let large = TypeFlattenCounter()
        _ = enriching(corpus(typeCount: 10, extensionCount: 10), counting: small)
        _ = enriching(corpus(typeCount: 1_000, extensionCount: 10), counting: large)

        #expect(small.count == large.count)
    }

    /// 1,000 extensions over 1,000 types: every extension's member reaches its own target, and no
    /// extension survives as a type of its own.
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

    /// The lookups are updated in place as extensions merge, so an extension can target a nested
    /// type that an *earlier* extension contributed — which is what re-flattening per extension used
    /// to give for free, and what a single up-front flatten would silently drop.
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

    /// A chain of extensions each adding the next nesting level, resolved in one pass.
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

    /// Generic arguments are stripped from the target name, so `extension Box<T>` finds `Box`.
    @Test func genericArgumentsAreStrippedFromTheTargetName() {
        let box = type("Box", kind: .struct)
        let ext = type("Box<T>", members: [member("mapped")], extensionOf: "Box<T>")

        let resolved = artifact([box, ext]).enriched()

        #expect(resolved.flattened().first { $0.id == "Box" }?.members.map(\.name) == ["mapped"])
    }

    /// An extension whose bare target name is shared by two modules stays unresolved and is dropped,
    /// rather than being bound to whichever type the index happened to register first.
    @Test func ambiguousBareNameAcrossModulesIsStillDropped() {
        let first = type("Node", module: "A", file: "A/Sources/A/Node.swift")
        let second = type("Node", module: "B", file: "B/Sources/B/Node.swift")
        let ext = type(
            "Node", members: [member("added")], extensionOf: "Node",
            module: "C", file: "C/Sources/C/Node+Extra.swift")

        let resolved = artifact([first, second, ext].map { $0 }).enriched()

        #expect(resolved.flattened().allSatisfy { $0.members.isEmpty })
    }
}
