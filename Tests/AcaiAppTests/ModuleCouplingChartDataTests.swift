import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Chart-data-from-metrics coverage. `ModuleCouplingChartData` is a pure mapping over
/// `CodeMetrics.ModuleCoupling` — no artifact/git fixture needed, just already-computed metric
/// values, so these exercise the zone classification and ranking directly.
///
/// `CodeMetrics.ModuleCoupling` has no public memberwise initializer (a `public struct`'s
/// synthesized memberwise init is internal-only unless the type declares its own) — its genuine
/// public construction path from outside `AcaiCore` is `Decodable`, so fixtures are built via JSON
/// rather than reaching into `AcaiCore` to add an init this pass has no other need for.
@Suite("Module Coupling Chart Data")
struct ModuleCouplingChartDataTests {

    private func module(
        name: String, instability: Double, abstractness: Double, distance: Double
    ) throws -> CodeMetrics.ModuleCoupling {
        let json = """
        {"name":"\(name)","typeCount":1,"afferentCoupling":0,"efferentCoupling":0,
         "instability":\(instability),"abstractness":\(abstractness),"distanceFromMainSequence":\(distance),
         "publicMemberCount":0,"stableDependencyViolations":[]}
        """
        return try JSONDecoder().decode(CodeMetrics.ModuleCoupling.self, from: Data(json.utf8))
    }

    @Test("A module on the main sequence is balanced")
    func onLineIsBalanced() throws {
        let data = ModuleCouplingChartData(
            modules: [try module(name: "M", instability: 0.5, abstractness: 0.5, distance: 0)])
        #expect(data.points.first?.zone == .balanced)
    }

    @Test("Stable and concrete, far from the line, is the Zone of Pain")
    func stableConcreteIsPainful() throws {
        let data = ModuleCouplingChartData(
            modules: [try module(name: "Core", instability: 0.05, abstractness: 0.0, distance: 0.95)])
        #expect(data.points.first?.zone == .painful)
    }

    @Test("Unstable and abstract, far from the line, is the Zone of Uselessness")
    func unstableAbstractIsUseless() throws {
        let data = ModuleCouplingChartData(
            modules: [try module(name: "Plugin", instability: 0.95, abstractness: 1.0, distance: 0.95)])
        #expect(data.points.first?.zone == .useless)
    }

    @Test("A small distance stays balanced regardless of instability")
    func smallDistanceStaysBalanced() throws {
        let data = ModuleCouplingChartData(
            modules: [try module(name: "Near", instability: 0.1, abstractness: 0.85, distance: 0.05)])
        #expect(data.points.first?.zone == .balanced)
    }

    @Test("rankedByDistance sorts farthest-from-the-line first")
    func rankedByDistanceSortsDescending() throws {
        let data = ModuleCouplingChartData(modules: [
            try module(name: "Close", instability: 0.5, abstractness: 0.5, distance: 0.1),
            try module(name: "Far", instability: 0.9, abstractness: 0.9, distance: 0.8),
            try module(name: "Mid", instability: 0.3, abstractness: 0.3, distance: 0.4)
        ])
        #expect(data.rankedByDistance.map(\.name) == ["Far", "Mid", "Close"])
    }

    @Test("Every module produces exactly one point")
    func onePointPerModule() throws {
        let data = ModuleCouplingChartData(modules: [
            try module(name: "A", instability: 0, abstractness: 1, distance: 0),
            try module(name: "B", instability: 1, abstractness: 0, distance: 0)
        ])
        #expect(data.points.count == 2)
        #expect(Set(data.points.map(\.id)) == ["A", "B"])
    }
}
