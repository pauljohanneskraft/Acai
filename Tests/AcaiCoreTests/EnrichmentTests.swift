import Testing
import Foundation
@testable import AcaiCore

/// Regression tests for the AcaiCore enrichment passes
/// (BUG-1/2/3/6/7/11/12 and GAP-7/8/9).
@Suite("Core: Enrichment Passes")
struct EnrichmentTests {

    private func type(
        _ name: String,
        kind: TypeKind = .struct,
        accessLevel: AccessLevel = .internal,
        members: [Member] = [],
        inherited: [String] = [],
        nested: [TypeDeclaration] = [],
        extensionOf: String? = nil,
        file: String = "M/Sources/M/\(UUID().uuidString).swift"
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name,
            kind: extensionOf == nil ? kind : .extension,
            accessLevel: accessLevel,
            inheritedTypes: inherited.map { TypeReference(name: $0) },
            members: members, nestedTypes: nested,
            extensionOf: extensionOf,
            location: SourceLocation(filePath: file, line: 1, column: 1)
        )
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels)
    }

    // MARK: GAP-8 — inferred multiplicity labels

    @Test func optionalScalarPropertyYieldsZeroOrOneMultiplicity() {
        let car = type("Car", kind: .class, accessLevel: .public, members: [
            Member(name: "engine", kind: .property,
                accessLevel: .internal, type: TypeReference(name: "Engine", isOptional: true))
        ])
        let engine = type("Engine", kind: .class, accessLevel: .public)
        let resolved = artifact([car, engine]).enriched()

        let edge = resolved.relationships.first { $0.source == "Car" && $0.target == "Engine" }
        #expect(edge?.targetLabel == "0..1")
    }

    @Test func scalarAndCollectionPropertiesKeepOneAndStarMultiplicities() {
        let car = type("Car", kind: .class, accessLevel: .public, members: [
            Member(name: "engine", kind: .property, accessLevel: .internal, type: TypeReference(name: "Engine")),
            Member(name: "wheels", kind: .property,
                accessLevel: .internal, type: TypeReference(name: "Wheel", isArray: true))
        ])
        let resolved = artifact([car, type("Engine", kind: .class,
            accessLevel: .public), type("Wheel", kind: .class, accessLevel: .public)]).enriched()

        #expect(resolved.relationships.first { $0.target == "Engine" }?.targetLabel == "1")
        #expect(resolved.relationships.first { $0.target == "Wheel" }?.targetLabel == "*")
    }

    // MARK: Stereotypes (kind + annotations)

    @Test func annotationStereotypeWinsOverKind() {
        var user = type("User", kind: .class, accessLevel: .public)
        user.annotations = ["@Entity"]
        // The annotation → stereotype map is injected (it lives in a language's configuration now).
        #expect(user.stereotype(annotationStereotypes: ["entity": "entity"]) == "entity")
        // With no annotation map, falls back to the kind (a class has none).
        #expect(user.stereotype(annotationStereotypes: [:]) == nil)
    }

    @Test func kindStereotypeUsedWhenNoKnownAnnotation() {
        var widget = type("Widget", kind: .protocol, accessLevel: .public)
        widget.annotations = ["@SomethingUnknown"]
        #expect(widget.stereotype() == "interface")
    }

    @Test func annotationStereotypeToleratesWhitespaceNewlinesAndQualifiers() {
        // Leading whitespace/newlines, package qualifiers and argument lists must still match.
        var user = type("User", kind: .class, accessLevel: .public)
        user.annotations = ["\n  @jakarta.persistence.Table(name = \"users\")"]
        #expect(user.stereotype(annotationStereotypes: ["table": "entity"]) == "entity")
    }

    // MARK: BUG-1 / BUG-2 / BUG-6 — extension relationships

    @Test func extensionResolutionMergesMembersWithoutDanglingOrDuplicateEdges() {
        let base = type("Foo", kind: .struct, accessLevel: .public)
        let ext = type("Foo", members: [Member(name: "extra", kind: .method, accessLevel: .internal)],
                       extensionOf: "Foo")
        var extWithConformance = ext
        extWithConformance.inheritedTypes = [TypeReference(name: "Bar")]
        let proto = type("Bar", kind: .protocol, accessLevel: .public)

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

    /// A protocol conformance declared on an `extension` (not the base declaration) must survive
    /// onto the merged type's own `inheritedTypes` — not just as a derived `Relationship` edge —
    /// so consumers that read `TypeDeclaration.inheritedTypes` directly (e.g. `DeadCodeScan`'s
    /// protocol-witness exemption) see it too.
    @Test func extensionConformanceSurvivesOntoMergedTypeInheritedTypes() {
        let base = type("Foo", kind: .struct, accessLevel: .public, inherited: ["Baseline"])
        var ext = type("Foo", extensionOf: "Foo")
        ext.inheritedTypes = [TypeReference(name: "Bar")]
        let resolved = artifact([base, ext]).enriched()

        let foo = resolved.types.first { $0.name == "Foo" }
        let names = Set(foo?.inheritedTypes.map(\.name) ?? [])
        #expect(names.isSuperset(of: ["Baseline", "Bar"]))
    }

    /// The same conformance, appearing on both the base declaration and an extension, must not be
    /// duplicated after merge.
    @Test func extensionConformanceAlreadyOnBaseIsNotDuplicated() {
        let base = type("Foo", kind: .struct, accessLevel: .public, inherited: ["Bar"])
        var ext = type("Foo", extensionOf: "Foo")
        ext.inheritedTypes = [TypeReference(name: "Bar")]
        let resolved = artifact([base, ext]).enriched()

        let foo = resolved.types.first { $0.name == "Foo" }
        #expect(foo?.inheritedTypes.filter { $0.name == "Bar" }.count == 1)
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
        let inner = type("Inner", kind: .struct, accessLevel: .public)
        var innerNested = inner
        innerNested.id = "Outer.Inner"
        innerNested.qualifiedName = "Outer.Inner"
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .struct,
            accessLevel: .public,
            nestedTypes: [innerNested],
            location: SourceLocation(filePath: "M/Sources/M/O.swift", line: 1, column: 1))
        var ext = type("Outer.Inner", members: [Member(name: "added", kind: .method, accessLevel: .internal)],
                       extensionOf: "Outer.Inner")
        ext.id = "extension.Outer.Inner"

        let resolved = artifact([outer, ext]).enriched()
        let mergedInner = resolved.types.first { $0.name == "Outer" }?.nestedTypes.first
        #expect(mergedInner?.members.contains { $0.name == "added" } == true)
        #expect(resolved.types.filter { $0.kind == .extension }.isEmpty)
    }

    // MARK: RC-F — bare-name extension-target fallback is module-scoped

    /// `extension Node { ... }` on an *external* type (e.g. `SwiftTreeSitter.Node`) must not
    /// silently merge into an unrelated in-project nested type that happens to share the bare name
    /// (`FreeformDiagram.Node`) just because it's the only declared `Node` — the extension's own
    /// module (`AcaiTreeSitter`) doesn't match the nested type's module (`AcaiApp`), so the fallback
    /// must refuse to guess and drop the extension like any other external-type extension.
    @Test func bareNameExtensionDoesNotMergeAcrossModules() {
        var nestedNode = type(
            "Node", kind: .struct, accessLevel: .public,
            file: "AcaiApp/Sources/AcaiApp/FreeformDiagram.swift")
        nestedNode.id = "FreeformDiagram.Node"
        nestedNode.qualifiedName = "FreeformDiagram.Node"
        let outer = TypeDeclaration(
            id: "FreeformDiagram", name: "FreeformDiagram", qualifiedName: "FreeformDiagram",
            kind: .struct, accessLevel: .public,
            nestedTypes: [nestedNode],
            location: SourceLocation(filePath: "AcaiApp/Sources/AcaiApp/FreeformDiagram.swift", line: 1, column: 1))
        let ext = type(
            "Node", members: [Member(name: "allChildren", kind: .method, accessLevel: .internal)],
            extensionOf: "Node",
            file: "AcaiTreeSitter/Sources/AcaiTreeSitter/Node+Children.swift")

        let resolved = artifact([outer, ext]).enriched()

        let mergedNode = resolved.types.first { $0.name == "FreeformDiagram" }?.nestedTypes.first
        #expect(mergedNode?.members.contains { $0.name == "allChildren" } == false)
        // Dropped like any other external-type extension: no leftover extension node either.
        #expect(resolved.types.filter { $0.kind == .extension }.isEmpty)
    }

    /// The bare-name fallback still works when the extension and its nested target genuinely share
    /// a module — module-scoping must not break the legitimate case.
    @Test func bareNameExtensionMergesIntoSameModuleNestedType() {
        var nestedNode = type(
            "Node", kind: .struct, accessLevel: .public,
            file: "AcaiApp/Sources/AcaiApp/FreeformDiagram.swift")
        nestedNode.id = "FreeformDiagram.Node"
        nestedNode.qualifiedName = "FreeformDiagram.Node"
        let outer = TypeDeclaration(
            id: "FreeformDiagram", name: "FreeformDiagram", qualifiedName: "FreeformDiagram",
            kind: .struct, accessLevel: .public,
            nestedTypes: [nestedNode],
            location: SourceLocation(filePath: "AcaiApp/Sources/AcaiApp/FreeformDiagram.swift", line: 1, column: 1))
        let ext = type(
            "Node", members: [Member(name: "helper", kind: .method, accessLevel: .internal)],
            extensionOf: "Node",
            file: "AcaiApp/Sources/AcaiApp/Node+Extras.swift")

        let resolved = artifact([outer, ext]).enriched()

        let mergedNode = resolved.types.first { $0.name == "FreeformDiagram" }?.nestedTypes.first
        #expect(mergedNode?.members.contains { $0.name == "helper" } == true)
    }

    // MARK: WS6 — deferred call-site receiver resolution (cross-file + multi-hop)

    private func method(_ name: String, callSites: [CallSite] = []) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, callSites: callSites)
    }

    /// `.unresolvedTypeName` promotes to `.type` once the full project (not just the caller's own
    /// file) shows exactly one declared type with that name — the cross-file case (`TypeName.method()`
    /// where `TypeName` is declared in a different file than the call site).
    @Test func unresolvedTypeNameResolvesAcrossFiles() {
        let caller = type("Caller", members: [
            method("run", callSites: [
                CallSite(receiver: .unresolvedTypeName("Helper"), methodName: "assist")
            ])
        ])
        let helper = type("Helper", members: [method("assist")])
        let resolved = artifact([caller, helper]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Caller" }?.members.first?.callSites.first
        #expect(site?.receiver == .type("Helper"))
    }

    /// Two declared types sharing a bare name is a real ambiguity (unlike the `mergeExtension`
    /// module-scoped case) — an `.unresolvedTypeName` must stay deferred rather than guess between
    /// them.
    @Test func unresolvedTypeNameStaysUnresolvedWhenAmbiguous() {
        let caller = type("Caller", members: [
            method("run", callSites: [
                CallSite(receiver: .unresolvedTypeName("Helper"), methodName: "assist")
            ])
        ])
        let helperA = type("Helper", nested: [], file: "A/Sources/A/Helper.swift")
        let helperB = type("Helper", nested: [], file: "B/Sources/B/Helper.swift")
        let resolved = artifact([caller, helperA, helperB]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Caller" }?.members.first?.callSites.first
        #expect(site?.receiver == .unresolvedTypeName("Helper"))
    }

    /// `.propertyChain(headTypeName:hops:)` promotes to `.type` when every hop resolves to a single,
    /// unambiguous declared property type — the multi-hop case (`model.diagrams.add()`, where
    /// `model`'s type is known but `diagrams` isn't a property of the *caller's* type).
    @Test func propertyChainResolvesThroughIntermediateHop() {
        let diagrams = type("Diagrams", members: [method("add")])
        let model = type("Model", members: [
            Member(name: "diagrams", kind: .property, accessLevel: .internal, type: TypeReference(name: "Diagrams"))
        ])
        let worker = type("Worker", members: [
            method("run", callSites: [
                CallSite(receiver: .propertyChain(headTypeName: "Model", hops: ["diagrams"]), methodName: "add")
            ])
        ])
        let resolved = artifact([worker, model, diagrams]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Worker" }?.members.first?.callSites.first
        #expect(site?.receiver == .type("Diagrams"))
    }

    /// A hop that isn't a real property of the head's type must not be guessed — the chain stays
    /// deferred (never promoted, never dropped to `.unknown` either — a consumer that runs before or
    /// without this pass already treats it the same as `.unknown`).
    @Test func propertyChainStaysUnresolvedWhenHopIsUnknown() {
        let model = type("Model", members: [])
        let worker = type("Worker", members: [
            method("run", callSites: [
                CallSite(receiver: .propertyChain(headTypeName: "Model", hops: ["nonexistent"]), methodName: "add")
            ])
        ])
        let resolved = artifact([worker, model]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Worker" }?.members.first?.callSites.first
        #expect(site?.receiver == .propertyChain(headTypeName: "Model", hops: ["nonexistent"]))
    }

    // MARK: BUG-3 — class conformance reclassified, true superclass kept

    @Test func inheritanceToProtocolBecomesConformance() {
        let proto = type("Drawable", kind: .protocol, accessLevel: .public)
        let base = type("Base", kind: .class, accessLevel: .public)
        let child = type("Child", kind: .class, accessLevel: .public)
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
            accessLevel: .public,
            location: SourceLocation(filePath: "M/Sources/M/W.swift", line: 1, column: 1))
        let wrapper = TypeDeclaration(
            id: "Wrapper", name: "Wrapper", qualifiedName: "Wrapper", kind: .struct,
            accessLevel: .public,
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
        let engine = type("Engine", kind: .struct, accessLevel: .public)
        let car = type("Car", kind: .struct, accessLevel: .public, members: [
            Member(name: "engine", kind: .property, accessLevel: .internal, type: TypeReference(name: "Engine")),
            Member(name: "wheels", kind: .property,
                   accessLevel: .internal,
                   type: TypeReference(name: "Array", genericArguments: [TypeReference(name: "Wheel")], isArray: true)),
            Member(name: "start", kind: .method, accessLevel: .internal, type: TypeReference(name: "Engine"))
        ])
        let wheel = type("Wheel", kind: .struct, accessLevel: .public)
        let resolved = artifact([engine, car, wheel]).enriched()
        let kinds = Dictionary(grouping: resolved.relationships.filter { $0.source == "Car" },
                               by: { $0.target }).mapValues { $0.map(\.kind) }
        #expect(kinds["Engine"]?.contains(.composition) == true)
        #expect(kinds["Wheel"]?.contains(.aggregation) == true)
    }

    // MARK: GAP-9 — typealias underlying-type dependency

    @Test func typeAliasProducesDependencyEdge() {
        let target = type("Money", kind: .struct, accessLevel: .public)
        let alias = type("Currency", kind: .typeAlias, inherited: ["Money"])
        let resolved = artifact([target, alias]).enriched()
        #expect(resolved.relationships.contains {
            $0.source == "Currency" && $0.target == "Money" && $0.kind == .dependency
        })
    }
}
