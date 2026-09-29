import Foundation
import Testing
@testable import AcaiCore

/// The zone thresholds themselves, exercised directly rather than through a renderer, since three
/// surfaces (the CLI/MCP coupling diagram and the app's chart) now classify against this one type.
@Suite("Main Sequence Zone")
struct MainSequenceZoneTests {

    @Test("A module on the line is balanced whichever end it sits at")
    func onLineIsBalanced() {
        #expect(MainSequenceZone(instability: 1, distanceFromMainSequence: 0) == .balanced)
        #expect(MainSequenceZone(instability: 0, distanceFromMainSequence: 0) == .balanced)
    }

    @Test("Stable and concrete is the zone of pain, unstable and abstract the zone of uselessness")
    func offLineSplitsByInstability() {
        #expect(MainSequenceZone(instability: 0.0, distanceFromMainSequence: 0.67) == .painful)
        #expect(MainSequenceZone(instability: 1.0, distanceFromMainSequence: 0.67) == .useless)
    }

    /// The band is inclusive at `0.3`, so a module exactly on the boundary is already classified —
    /// pinned because the app's chart previously owned this number and now reads it from here.
    @Test("The balanced band ends at a distance of 0.3")
    func boundaryIsInclusive() {
        #expect(MainSequenceZone(instability: 0.2, distanceFromMainSequence: 0.29) == .balanced)
        #expect(MainSequenceZone(instability: 0.2, distanceFromMainSequence: 0.3) == .painful)
    }

    @Test("Instability of exactly 0.5 counts as unstable")
    func halfInstabilityIsUseless() {
        #expect(MainSequenceZone(instability: 0.5, distanceFromMainSequence: 0.4) == .useless)
    }

    @Test("A module's zone agrees with its own metrics")
    func moduleCouplingDerivesItsZone() throws {
        let json = """
        {"name":"Core","typeCount":3,"linesOfCode":0,"afferentCoupling":2,"efferentCoupling":0,
         "instability":0.0,"abstractness":0.33,"distanceFromMainSequence":0.67,
         "publicMemberCount":0,"stableDependencyViolations":[]}
        """
        let module = try JSONDecoder().decode(CodeMetrics.ModuleCoupling.self, from: Data(json.utf8))
        #expect(module.mainSequenceZone == .painful)
        #expect(module.mainSequenceZone.label == "zone of pain")
    }
}
