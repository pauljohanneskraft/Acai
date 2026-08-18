import Testing
@testable import AcaiApp

/// `ActivityProgressGate` is what keeps a noisy source (libgit2's transfer-progress callback fires
/// on every packet) from queuing a main-actor hop per call — `ActivityCenter`'s progress-reporting
/// `run` overload gates every report through one before publishing it.
@Suite("ActivityProgressGate")
struct ActivityProgressGateTests {
    @Test func firstValueAlwaysAdvances() {
        let gate = ActivityProgressGate()
        #expect(gate.advance(to: 0.0))
    }

    @Test func aSubOnePercentMoveIsSuppressed() {
        let gate = ActivityProgressGate()
        #expect(gate.advance(to: 0.10))
        #expect(!gate.advance(to: 0.105))
    }

    @Test func aOnePercentOrGreaterMoveAdvances() {
        let gate = ActivityProgressGate()
        #expect(gate.advance(to: 0.10))
        #expect(gate.advance(to: 0.15))
    }

    @Test func completionAlwaysAdvancesEvenFromNearOne() {
        let gate = ActivityProgressGate()
        #expect(gate.advance(to: 0.999))
        #expect(gate.advance(to: 1.0))
    }
}
