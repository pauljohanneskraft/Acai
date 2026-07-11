import Testing
@testable import UMLCore
@testable import UMLDiagram

/// Covers `DeadCodeScan`: an uncalled private method is a candidate; a called method, a public method,
/// an override, and a marked entry point are all excluded; coverage is reported.
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

    private func artifact() -> CodeArtifact {
        // `entry` calls `used`; `unused` is called by nobody.
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
        // Without the language markers, `lifecycle` (@Test) is no longer excluded, but public/override
        // members still are.
        let report = DeadCodeScan(
            artifact: artifact(),
            languages: LanguageConfigurationResolver(single: LanguageConfiguration())).report
        #expect(report.candidates.map(\.id).sorted() == ["Service.lifecycle", "Service.unused"])
    }

    /// A bare `foo()` reaches the scan as a `.selfDispatch` call site; the private method it targets
    /// must be marked used, not reported dead. Locks in the extraction fix at the scan level.
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
    /// so it is never a dead-code candidate even when non-public and uncalled (RC3).
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
        // `run` is a witness (excluded); only the genuinely-uncalled `orphan` is reported.
        #expect(report.candidates.map(\.id) == ["Tool.orphan"])
    }
}
