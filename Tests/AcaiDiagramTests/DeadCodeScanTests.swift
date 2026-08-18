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
}
