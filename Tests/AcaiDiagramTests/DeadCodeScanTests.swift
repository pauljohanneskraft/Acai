import Testing
@testable import AcaiCore
@testable import AcaiDiagram

@Suite("Dead-code scan")
struct DeadCodeScanTests {

    private func method(
        _ name: String,
        access: AccessLevel = .private,
        modifiers: [Modifier] = [],
        annotations: [String] = [],
        calls: [CallSite] = []
    ) -> Member {
        Member(
            name: name, kind: .method, accessLevel: access, modifiers: modifiers, annotations: annotations,
            location: SourceLocation(filePath: "S.swift", line: 1, column: 1), callSites: calls)
    }

    private func member(
        _ name: String,
        kind: MemberKind,
        access: AccessLevel = .private,
        modifiers: [Modifier] = [],
        annotations: [String] = []
    ) -> Member {
        Member(
            name: name, kind: kind, accessLevel: access, modifiers: modifiers, annotations: annotations,
            location: SourceLocation(filePath: "S.swift", line: 1, column: 1))
    }

    /// A language that records calls to every kind, so the scan's own per-kind behaviour can be
    /// pinned independently of what any real parser happens to record today.
    private func scanning(_ kinds: Set<MemberKind>) -> LanguageConfigurationResolver {
        LanguageConfigurationResolver(single: LanguageConfiguration(deadCodeMemberKinds: kinds))
    }

    private func report(
        _ types: [TypeDeclaration], scanning kinds: Set<MemberKind> = [.method]
    ) -> DeadCodeScan.Report {
        DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types),
            languages: scanning(kinds)).report
    }

    private func widget(_ members: [Member], kind: TypeKind = .class) -> TypeDeclaration {
        TypeDeclaration(
            id: "Widget", name: "Widget", qualifiedName: "Widget", kind: kind, accessLevel: .public,
            members: members, location: SourceLocation(filePath: "Widget.swift", line: 1, column: 1))
    }

    private func artifact() -> CodeArtifact {
        let service = TypeDeclaration(
            id: "Service", name: "Service", qualifiedName: "Service", kind: .class, accessLevel: .public,
            members: [
                method("entry", access: .public, calls: [CallSite(receiver: .type("Service"), methodName: "used")]),
                method("used"),
                method("unused"),
                method("publicButUncalled", access: .public),
                method("overridden", modifiers: [.override]),
                method("lifecycle", annotations: ["@Test"])
            ],
            location: SourceLocation(filePath: "Service.swift", line: 1, column: 1))
        return CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [service])
    }

    @Test func onlyUncalledNonEntryPrivateMethodIsCandidate() {
        let report = DeadCodeScan(
            artifact: artifact(),
            languages: LanguageConfigurationResolver(
                single: LanguageConfiguration(entryPointMarkers: EntryPointMarkers(annotations: ["test"])))).report

        #expect(report.candidates.map(\.id) == ["Service.unused"])
        // A resolved call to `used` means coverage is 100%.
        #expect(report.coverage.fraction == 1)
    }

    @Test func markerlessScanStillExcludesUniversalEntryPoints() {
        let report = DeadCodeScan(
            artifact: artifact(),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.map(\.id).sorted() == ["Service.lifecycle", "Service.unused"])
    }

    /// A bare `foo()` reaches the scan as a `.selfDispatch` call site; the private method it targets
    /// must be marked used, not reported dead.
    @Test func bareSelfCallMarksPrivateMethodUsed() {
        let service = TypeDeclaration(
            id: "Service", name: "Service", qualifiedName: "Service", kind: .class, accessLevel: .public,
            members: [
                method("entry", access: .public, calls: [CallSite(receiver: .selfDispatch, methodName: "used")]),
                method("used")
            ],
            location: SourceLocation(filePath: "Service.swift", line: 1, column: 1))
        let report = DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [service]),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.isEmpty)
    }

    /// An abstract method is a body-less contract implemented by subtypes and reached polymorphically,
    /// so it is never a dead-code candidate even when non-public and uncalled.
    @Test func abstractMethodIsNotACandidate() {
        let base = TypeDeclaration(
            id: "Base", name: "Base", qualifiedName: "Base", kind: .class, accessLevel: .internal,
            members: [method("hook", modifiers: [.abstract])],
            location: SourceLocation(filePath: "Base.swift", line: 1, column: 1))
        let report = DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [base]),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.isEmpty)
    }

    /// A non-public method that satisfies a requirement of an in-artifact protocol the type conforms to
    /// is a witness — reached through the conformance, so never a candidate even with no call edge.
    @Test func protocolWitnessIsNotACandidate() {
        let proto = TypeDeclaration(
            id: "Runnable", name: "Runnable", qualifiedName: "Runnable", kind: .protocol, accessLevel: .public,
            members: [method("run", access: .public)],
            location: SourceLocation(filePath: "Runnable.swift", line: 1, column: 1))
        let tool = TypeDeclaration(
            id: "Tool", name: "Tool", qualifiedName: "Tool", kind: .struct, accessLevel: .internal,
            inheritedTypes: [TypeReference(name: "Runnable")],
            members: [method("run"), method("orphan")],
            location: SourceLocation(filePath: "Tool.swift", line: 1, column: 1))
        let report = DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [proto, tool]),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.map(\.id) == ["Tool.orphan"])
    }

    /// Two declared types sharing a simple name each call their own method by self-dispatch; neither
    /// call may be lost to the other's node, so neither `used` is reported dead.
    @Test func sameSimpleNameInDifferentModulesAreScoredSeparately() {
        let configA = TypeDeclaration(
            id: "ModuleA.Config", name: "Config", qualifiedName: "ModuleA.Config", kind: .class,
            accessLevel: .public,
            members: [
                method("run", access: .public, calls: [CallSite(receiver: .selfDispatch, methodName: "used")]),
                method("used")
            ],
            location: SourceLocation(filePath: "ModuleA/Config.swift", line: 1, column: 1))
        let configB = TypeDeclaration(
            id: "ModuleB.Config", name: "Config", qualifiedName: "ModuleB.Config", kind: .class,
            accessLevel: .public,
            members: [
                method("run", access: .public, calls: [CallSite(receiver: .selfDispatch, methodName: "used")]),
                method("used")
            ],
            location: SourceLocation(filePath: "ModuleB/Config.swift", line: 1, column: 1))
        let report = DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [configA, configB]),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.isEmpty)
    }

    // MARK: - Member kinds

    /// An uncalled initializer is a candidate where the language opts the kind in, and the identical
    /// declaration is invisible where it does not — the whole point of `deadCodeMemberKinds`.
    @Test func anUncalledInitializerIsACandidateOnlyWhereTheLanguageScansInitializers() {
        let types = [widget([member("init", kind: .initializer)])]
        #expect(report(types, scanning: [.method, .initializer]).candidates.map(\.id) == ["Widget.init"])
        #expect(report(types).candidates.isEmpty)
    }

    @Test func aCalledInitializerIsNotACandidate() {
        let types = [widget([
            method("make", access: .public, calls: [CallSite(receiver: .type("Widget"), methodName: "init")]),
            member("init", kind: .initializer)
        ])]
        #expect(report(types, scanning: [.method, .initializer]).candidates.isEmpty)
    }

    @Test func anUncalledSubscriptIsACandidateOnlyWhereTheLanguageScansSubscripts() {
        let types = [widget([member("subscript", kind: .subscript)])]
        #expect(report(types, scanning: [.method, .subscript]).candidates.map(\.id) == ["Widget.subscript"])
        #expect(report(types).candidates.isEmpty)
    }

    @Test func aCalledSubscriptIsNotACandidate() {
        let types = [widget([
            method("read", access: .public, calls: [CallSite(receiver: .type("Widget"), methodName: "subscript")]),
            member("subscript", kind: .subscript)
        ])]
        #expect(report(types, scanning: [.method, .subscript]).candidates.isEmpty)
    }

    /// A deinitializer is never called by name, so the question doesn't apply — and no language opts
    /// the kind in. Scanned only if one explicitly asked, which none does.
    @Test func aDeinitializerIsNotACandidate() {
        let types = [widget([member("deinit", kind: .deinitializer)])]
        #expect(report(types, scanning: [.method, .initializer, .subscript]).candidates.isEmpty)
    }

    /// The `isEntryPoint` rules are the member's, not the method's: each exemption that spares a
    /// method spares an initializer too.
    @Test func theSameEntryPointRulesExemptAnInitializer() {
        let types = [widget([
            member("init", kind: .initializer, access: .public),
            member("init", kind: .initializer, modifiers: [.override]),
            member("init", kind: .initializer, modifiers: [.abstract]),
            member("init", kind: .initializer, annotations: ["@Test"])
        ])]
        let scan = DeadCodeScan(
            artifact: CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types),
            languages: LanguageConfigurationResolver(
                single: LanguageConfiguration(
                    entryPointMarkers: EntryPointMarkers(annotations: ["test"]),
                    deadCodeMemberKinds: [.method, .initializer])))
        #expect(scan.report.candidates.isEmpty)
    }

    /// A protocol-required `init` is a witness like any other requirement.
    @Test func aProtocolRequiredInitializerIsAWitness() {
        let proto = TypeDeclaration(
            id: "Makeable", name: "Makeable", qualifiedName: "Makeable", kind: .protocol, accessLevel: .public,
            members: [member("init", kind: .initializer, access: .public)],
            location: SourceLocation(filePath: "Makeable.swift", line: 1, column: 1))
        let tool = TypeDeclaration(
            id: "Tool", name: "Tool", qualifiedName: "Tool", kind: .struct, accessLevel: .internal,
            inheritedTypes: [TypeReference(name: "Makeable")],
            members: [member("init", kind: .initializer)],
            location: SourceLocation(filePath: "Tool.swift", line: 1, column: 1))
        #expect(report([proto, tool], scanning: [.method, .initializer]).candidates.isEmpty)
    }

    /// A requirement witnesses its own kind only: an `init` requirement must not spare a *method*
    /// that happens to be called `init`, which name-only matching would have done.
    @Test func anInitializerRequirementDoesNotWitnessAMethodOfTheSameName() {
        let proto = TypeDeclaration(
            id: "Makeable", name: "Makeable", qualifiedName: "Makeable", kind: .protocol, accessLevel: .public,
            members: [member("init", kind: .initializer, access: .public)],
            location: SourceLocation(filePath: "Makeable.swift", line: 1, column: 1))
        let tool = TypeDeclaration(
            id: "Tool", name: "Tool", qualifiedName: "Tool", kind: .struct, accessLevel: .internal,
            inheritedTypes: [TypeReference(name: "Makeable")],
            members: [method("init")],
            location: SourceLocation(filePath: "Tool.swift", line: 1, column: 1))
        #expect(report([proto, tool]).candidates.map(\.id) == ["Tool.init"])
    }
}
