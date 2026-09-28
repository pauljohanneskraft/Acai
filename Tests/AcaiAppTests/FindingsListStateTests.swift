import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("Findings list state")
struct FindingsListStateTests {
    private let codebaseA = UUID()
    private let codebaseB = UUID()

    private func finding(
        _ id: String, kind: Finding.Kind = .violation, severity: Finding.Severity = .warning,
        codebaseID: UUID? = nil, indexedAt: Date? = nil
    ) -> Finding {
        Finding(
            id: id, kind: kind, severity: severity, codebaseID: codebaseID ?? codebaseA, codebaseName: "C",
            title: id, message: "", location: nil, reference: nil, indexedAt: indexedAt, cycle: nil)
    }

    @Test func suppressedFindingHiddenUntilShowSuppressed() {
        let suppressed = finding("suppressed")
        let shown = finding("shown")
        var state = FindingsListState()
        state = state.toggling(suppressed)

        #expect(state.isSuppressed(suppressed))
        #expect(state.visible(from: [suppressed, shown]).map(\.id) == ["shown"])

        state.showSuppressed = true
        #expect(state.visible(from: [suppressed, shown]).map(\.id) == ["shown", "suppressed"])

        state = state.toggling(suppressed)
        #expect(!state.isSuppressed(suppressed))
    }

    @Test func sortsBySeverityThenRecencyThenID() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let findings = [
            finding("info-newer", severity: .info, indexedAt: newer),
            finding("warning-b", severity: .warning, indexedAt: newer),
            finding("warning-a", severity: .warning, indexedAt: newer),
            finding("warning-older", severity: .warning, indexedAt: older),
            finding("critical-unindexed", severity: .critical, indexedAt: nil),
            finding("critical-older", severity: .critical, indexedAt: older)
        ]

        #expect(FindingsListState().visible(from: findings).map(\.id) == [
            "critical-older", "critical-unindexed", "warning-a", "warning-b", "warning-older", "info-newer"
        ])
    }

    @Test func kindAndCodebaseFiltersCompose() {
        let findings = [
            finding("violation-a", kind: .violation, codebaseID: codebaseA),
            finding("deadCode-a", kind: .deadCode, codebaseID: codebaseA),
            finding("violation-b", kind: .violation, codebaseID: codebaseB),
            finding("health-b", kind: .health, codebaseID: codebaseB)
        ]
        var state = FindingsListState().toggling(.deadCode)

        #expect(state.visible(from: findings).map(\.id) == ["health-b", "violation-a", "violation-b"])

        state.codebaseID = codebaseB
        #expect(state.visible(from: findings).map(\.id) == ["health-b", "violation-b"])

        state = state.toggling(.deadCode)
        state.codebaseID = nil
        #expect(state.visible(from: findings).count == 4)
    }
}
