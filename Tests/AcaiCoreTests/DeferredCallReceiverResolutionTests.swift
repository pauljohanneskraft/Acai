import Testing
@testable import AcaiCore

/// Post-merge resolution of the deferred `CallReceiver` cases added alongside a dead-code
/// false-positive pass: `.unresolvedTypeName` with a dotted qualified path (fully-qualified
/// nested-type receivers), `.ownPropertyElement` (closure-`$0` array-element receivers), and
/// `.ownMethodReturn` (cross-file same-type method-return locals). See `EnrichmentTests` for the
/// original `.unresolvedTypeName`/`.propertyChain`/`.ownProperty` coverage this extends.
@Suite("Core: Deferred Call-Receiver Resolution")
struct DeferredCallReceiverResolutionTests {

    private func type(
        _ name: String,
        kind: TypeKind = .struct,
        accessLevel: AccessLevel = .internal,
        members: [Member] = [],
        nested: [TypeDeclaration] = [],
        file: String = "M/Sources/M/Caller.swift"
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name,
            kind: kind, accessLevel: accessLevel,
            members: members, nestedTypes: nested,
            location: SourceLocation(filePath: file, line: 1, column: 1)
        )
    }

    private func method(_ name: String, callSites: [CallSite] = []) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, callSites: callSites)
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    /// `.unresolvedTypeName` accepts a dotted qualified-path (`Outer.Inner`), not just a simple name —
    /// the fully-qualified nested-type receiver case (`Outer.Inner.method()`). An exact `qualifiedName`
    /// match resolves even when the *simple* name alone is ambiguous project-wide (two unrelated
    /// nested types both named `Payload`), and the promoted `.type` carries the resolved declaration's
    /// own simple name, never the dotted path (the producer contract `.type` requires).
    @Test func unresolvedTypeNameResolvesQualifiedPathDespiteAmbiguousSimpleName() {
        let innerA = TypeDeclaration(
            id: "OuterA.Payload", name: "Payload", qualifiedName: "OuterA.Payload", kind: .struct,
            accessLevel: .internal, members: [method("assist")],
            location: SourceLocation(filePath: "M/Sources/M/A.swift", line: 1, column: 1))
        let outerA = TypeDeclaration(
            id: "OuterA", name: "OuterA", qualifiedName: "OuterA", kind: .struct,
            accessLevel: .internal, nestedTypes: [innerA],
            location: SourceLocation(filePath: "M/Sources/M/A.swift", line: 1, column: 1))
        let innerB = TypeDeclaration(
            id: "OuterB.Payload", name: "Payload", qualifiedName: "OuterB.Payload", kind: .struct,
            accessLevel: .internal,
            location: SourceLocation(filePath: "M/Sources/M/B.swift", line: 1, column: 1))
        let outerB = TypeDeclaration(
            id: "OuterB", name: "OuterB", qualifiedName: "OuterB", kind: .struct,
            accessLevel: .internal, nestedTypes: [innerB],
            location: SourceLocation(filePath: "M/Sources/M/B.swift", line: 1, column: 1))
        let caller = type("Caller", members: [
            method("run", callSites: [
                CallSite(receiver: .unresolvedTypeName("OuterA.Payload"), methodName: "assist")
            ])
        ])
        let resolved = artifact([caller, outerA, outerB]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Caller" }?.members.first?.callSites.first
        #expect(site?.receiver == .type("Payload"))
    }

    /// `.ownPropertyElement` promotes to the *element* type of an array-typed stored property on the
    /// call site's own (fully-merged) enclosing type — the closure-`$0` receiver case
    /// (`items.map { $0.method() }` when `items` is declared in a sibling extension file). A
    /// non-array property (or an absent one) must not resolve — only an array's element is ever a
    /// valid receiver here.
    @Test func ownPropertyElementResolvesArrayPropertyElementType() {
        let item = type("Item", members: [method("describe")])
        let owner = type("Owner", members: [
            Member(
                name: "items", kind: .property, accessLevel: .internal,
                type: TypeReference(name: "Array", genericArguments: [TypeReference(name: "Item")], isArray: true)),
            method("run", callSites: [
                CallSite(receiver: .ownPropertyElement(propertyName: "items"), methodName: "describe")
            ])
        ])
        let resolved = artifact([owner, item]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Owner" }?.members.first { $0.name == "run" }?.callSites.first
        #expect(site?.receiver == .type("Item"))
    }

    @Test func ownPropertyElementStaysUnresolvedForNonArrayProperty() {
        let owner = type("Owner", members: [
            Member(name: "count", kind: .property, accessLevel: .internal, type: TypeReference(name: "Int")),
            method("run", callSites: [
                CallSite(receiver: .ownPropertyElement(propertyName: "count"), methodName: "describe")
            ])
        ])
        let resolved = artifact([owner]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Owner" }?.members.first { $0.name == "run" }?.callSites.first
        #expect(site?.receiver == .ownPropertyElement(propertyName: "count"))
    }

    /// `.ownMethodReturn` promotes to a same-type method's declared return type — the cross-file
    /// same-type method-return-local case (`let x = compute(); x.method()` when `compute()` is
    /// declared in a sibling extension file this call site's own file doesn't see).
    @Test func ownMethodReturnResolvesMethodReturnType() {
        let widget = type("Widget", members: [method("use")])
        let worker = type("Worker", members: [
            method("compute", callSites: []),
            method("run", callSites: [
                CallSite(receiver: .ownMethodReturn(methodName: "compute", remainingHops: []), methodName: "use")
            ])
        ])
        var computingWorker = worker
        computingWorker.members[0].type = TypeReference(name: "Widget")
        let resolved = artifact([computingWorker, widget]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Worker" }?.members.first { $0.name == "run" }?.callSites.first
        #expect(site?.receiver == .type("Widget"))
    }

    @Test func ownMethodReturnStaysUnresolvedWhenMethodIsAbsent() {
        let worker = type("Worker", members: [
            method("run", callSites: [
                CallSite(receiver: .ownMethodReturn(methodName: "missing", remainingHops: []), methodName: "use")
            ])
        ])
        let resolved = artifact([worker]).resolvingCallSiteReceivers()
        let site = resolved.types.first { $0.name == "Worker" }?.members.first { $0.name == "run" }?.callSites.first
        #expect(site?.receiver == .ownMethodReturn(methodName: "missing", remainingHops: []))
    }
}
