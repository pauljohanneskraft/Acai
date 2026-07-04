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
                method("entry", access: .public, calls: [CallSite(receiverType: "Service", methodName: "used")]),
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
            entryPoints: EntryPointMarkers(annotations: ["test"])).report

        #expect(report.candidates.map(\.id) == ["Service.unused"])
        // A resolved call to `used` means coverage is 100%.
        #expect(report.coverage.fraction == 1)
    }

    @Test func markerlessScanStillExcludesUniversalEntryPoints() {
        // Without the language markers, `lifecycle` (@Test) is no longer excluded, but public/override
        // members still are.
        let report = DeadCodeScan(artifact: artifact()).report
        #expect(report.candidates.map(\.id).sorted() == ["Service.lifecycle", "Service.unused"])
    }
}
