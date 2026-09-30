import Foundation
import Testing
import AcaiCore
import AcaiQuality
import AcaiRender
@testable import AcaiApp

@Suite("Finding from AtlasFinding")
struct FindingFromAtlasFindingTests {
    private let codebase = Codebase(id: UUID(), name: "App", directoryPath: "/tmp/App")

    @Test(arguments: AtlasFinding.Kind.allCases)
    func keepsTheKind(_ kind: AtlasFinding.Kind) {
        let finding = Finding(
            AtlasFinding(kind: kind, severity: .info, title: "T", message: "M", location: nil, identity: "T"),
            codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.kind.rawValue == kind.rawValue)
    }

    @Test(arguments: AtlasFinding.Severity.allCases)
    func keepsTheSeverity(_ severity: AtlasFinding.Severity) {
        let finding = Finding(
            AtlasFinding(kind: .health, severity: severity, title: "T", message: "M", location: nil, identity: "T"),
            codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.severity.rawValue == severity.rawValue)
    }

    @Test func theIDIsTheKindCodebaseAndSharedIdentity() {
        let violation = Violation(ruleKind: "budget", message: "M", subject: "Widget", detail: ["value": "3"])
        let finding = Finding(AtlasFinding(violation: violation), codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.id == "violation-\(codebase.id)-budget-Widget")
    }

    @Test func carriesTheSharedWordingAndTheCodebase() {
        let location = AcaiCore.SourceLocation(filePath: "Widget.swift", line: 3, column: 1)
        let finding = Finding(
            AtlasFinding(kind: .deadCode, severity: .info, title: "Widget.unused", message: "M", location: location,
                identity: "Widget.unused"),
            codebase: codebase, reference: nil, cycle: nil)
        #expect(finding.title == "Widget.unused")
        #expect(finding.message == "M")
        #expect(finding.location == location)
        #expect(finding.codebaseID == codebase.id)
        #expect(finding.codebaseName == "App")
    }
}
