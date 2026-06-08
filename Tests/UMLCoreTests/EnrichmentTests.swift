import Testing
import Foundation
@testable import UMLCore

/// Regression tests for the UMLCore enrichment passes
/// (BUG-1/2/3/6/7/11/12 and GAP-7/8/9).
@Suite("Core: Enrichment Passes")
struct EnrichmentTests {

    private func type(
        _ name: String,
        kind: TypeKind = .struct,
        members: [Member] = [],
        inherited: [String] = [],
        nested: [TypeDeclaration] = [],
        extensionOf: String? = nil,
        file: String = "M/Sources/M/\(UUID().uuidString).swift"
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name,
            kind: extensionOf == nil ? kind : .extension,
            inheritedTypes: inherited.map { TypeReference(name: $0) },
            members: members, nestedTypes: nested,
            extensionOf: extensionOf,
            location: SourceLocation(filePath: file, line: 1, column: 1)
        )
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels)
    }

    // MARK: BUG-1 / BUG-2 / BUG-6 — extension relationships

    @Test func extensionResolutionMergesMembersWithoutDanglingOrDuplicateEdges() {
        let base = type("Foo", kind: .struct)
        let ext = type("Foo", members: [Member(name: "extra", kind: .method)],
                       extensionOf: "Foo")
        var extWithConformance = ext
        extWithConformance.inheritedTypes = [TypeReference(name: "Bar")]
        let proto = type("Bar", kind: .protocol)

        let resolved = artifact([base, extWithConformance, proto]).enriched()

        // Extension node is gone; its members merged into Foo.
        #expect(resolved.types.filter { $0.kind == .extension }.isEmpty)
        let foo = resolved.types.first { $0.name == "Foo" }
        #expect(foo?.members.contains { $0.name == "extra" } == true)

        // Exactly one conformance edge Foo→Bar; no dangling `extension.*` source.
        let confs = resolved.relationships.filter { $0.kind == .conformance }
        #expect(confs.filter { $0.target == "Bar" }.count == 1)
        #expect(resolved.relationships.allSatisfy { !$0.source.hasPrefix("extension.") })
        #expect(resolved.relationships.allSatisfy { $0.kind != .extension })
    }

    @Test func externalTypeExtensionIsDroppedEntirely() {
        // `extension Array: CustomThing` where Array is not in the codebase.
        let ext = type("Array", extensionOf: "Array")
        var extWithConf = ext
        extWithConf.inheritedTypes = [TypeReference(name: "CustomThing")]
        let resolved = artifact([extWithConf]).enriched()
        #expect(resolved.types.isEmpty)
        // No leaked conformance edge with an external source.
        #expect(resolved.relationships.filter { $0.kind == .conformance }.isEmpty)
    }

    // MARK: BUG-7 — extension of a nested type resolves and merges

    @Test func extensionOfNestedTypeMerges() {
        let inner = type("Inner", kind: .struct)
        var innerNested = inner
        innerNested.id = "Outer.Inner"
        innerNested.qualifiedName = "Outer.Inner"
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .struct,
            nestedTypes: [innerNested],
            location: SourceLocation(filePath: "M/Sources/M/O.swift", line: 1, column: 1))
        var ext = type("Outer.Inner", members: [Member(name: "added", kind: .method)],
                       extensionOf: "Outer.Inner")
        ext.id = "extension.Outer.Inner"

        let resolved = artifact([outer, ext]).enriched()
        let mergedInner = resolved.types.first { $0.name == "Outer" }?.nestedTypes.first
        #expect(mergedInner?.members.contains { $0.name == "added" } == true)
        #expect(resolved.types.filter { $0.kind == .extension }.isEmpty)
    }

    // MARK: BUG-3 — class conformance reclassified, true superclass kept

    @Test func inheritanceToProtocolBecomesConformance() {
        let proto = type("Drawable", kind: .protocol)
        let base = type("Base", kind: .class)
        let child = type("Child", kind: .class)
        let rels = [
            Relationship(kind: .inheritance, source: "Child", target: "Base"),
            Relationship(kind: .inheritance, source: "Child", target: "Drawable")
        ]
        let resolved = artifact([proto, base, child], rels).enriched()
        let toProto = resolved.relationships.first { $0.target == "Drawable" }
        let toBase = resolved.relationships.first { $0.target == "Base" }
        #expect(toProto?.kind == .conformance)
        #expect(toBase?.kind == .inheritance)
    }

    // MARK: BUG-12 / GAP-7 — relationship endpoints resolve to ids incl. nested

    @Test func relationshipNamesResolveToNestedTypeIds() {
        let nested = TypeDeclaration(
            id: "Wrapper.Payload", name: "Payload", qualifiedName: "Wrapper.Payload", kind: .struct,
            location: SourceLocation(filePath: "M/Sources/M/W.swift", line: 1, column: 1))
        let wrapper = TypeDeclaration(
            id: "Wrapper", name: "Wrapper", qualifiedName: "Wrapper", kind: .struct,
            nestedTypes: [nested],
            location: SourceLocation(filePath: "M/Sources/M/W.swift", line: 1, column: 1))
        let user = type("User", inherited: [])
        let rels = [Relationship(kind: .dependency, source: "User", target: "Payload")]
        let resolved = artifact([wrapper, user], rels).enriched()
        #expect(resolved.relationships.contains {
            $0.source == "User" && $0.target == "Wrapper.Payload"
        })
        // flattened() exposes nested types with cleared nesting.
        #expect(resolved.flattened().map(\.id).contains("Wrapper.Payload"))
    }

    // MARK: GAP-8 — inferred structural edges

    @Test func propertyAndMethodTypesProduceStructuralEdges() {
        let engine = type("Engine", kind: .struct)
        let car = type("Car", kind: .struct, members: [
            Member(name: "engine", kind: .property, type: TypeReference(name: "Engine")),
            Member(name: "wheels", kind: .property,
                   type: TypeReference(name: "Array", genericArguments: [TypeReference(name: "Wheel")], isArray: true)),
            Member(name: "start", kind: .method, type: TypeReference(name: "Engine"))
        ])
        let wheel = type("Wheel", kind: .struct)
        let resolved = artifact([engine, car, wheel]).enriched()
        let kinds = Dictionary(grouping: resolved.relationships.filter { $0.source == "Car" },
                               by: { $0.target }).mapValues { $0.map(\.kind) }
        #expect(kinds["Engine"]?.contains(.composition) == true)
        #expect(kinds["Wheel"]?.contains(.aggregation) == true)
    }

    // MARK: GAP-9 — typealias underlying-type dependency

    @Test func typeAliasProducesDependencyEdge() {
        let target = type("Money", kind: .struct)
        let alias = type("Currency", kind: .typeAlias, inherited: ["Money"])
        let resolved = artifact([target, alias]).enriched()
        #expect(resolved.relationships.contains {
            $0.source == "Currency" && $0.target == "Money" && $0.kind == .dependency
        })
    }
}
