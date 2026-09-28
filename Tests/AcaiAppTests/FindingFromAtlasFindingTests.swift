import Foundation
import Testing
import AcaiCore
import AcaiRender
@testable import AcaiApp

@Suite("Finding from AtlasFinding")
struct FindingFromAtlasFindingTests {
    private let codebase = Codebase(id: UUID(), name: "App", directoryPath: "/tmp/App")

    @Test(arguments: AtlasFinding.Kind.allCases)
    func keepsTheKind(_ kind: AtlasFinding.Kind) {
        let finding = Finding(
            AtlasFinding(kind: kind, severity: .info, title: "T", message: "M", location: nil),
            id: "id", codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.kind.rawValue == kind.rawValue)
    }

    @Test(arguments: AtlasFinding.Severity.allCases)
    func keepsTheSeverity(_ severity: AtlasFinding.Severity) {
        let finding = Finding(
            AtlasFinding(kind: .health, severity: severity, title: "T", message: "M", location: nil),
            id: "id", codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.severity.rawValue == severity.rawValue)
    }

    @Test func carriesTheSharedWordingAndTheCodebase() {
        let location = AcaiCore.SourceLocation(filePath: "Widget.swift", line: 3, column: 1)
        let finding = Finding(
            AtlasFinding(kind: .deadCode, severity: .info, title: "Widget.unused", message: "M", location: location),
            id: "id", codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.title == "Widget.unused")
        #expect(finding.message == "M")
        #expect(finding.location == location)
        #expect(finding.codebaseID == codebase.id)
        #expect(finding.codebaseName == "App")
    }
}
