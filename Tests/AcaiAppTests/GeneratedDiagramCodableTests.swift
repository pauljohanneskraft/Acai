import Foundation
import Testing
import AcaiDiagram
import AcaiRender
import AcaiQuality
@testable import AcaiApp

/// Round-trip coverage for the `GeneratedDiagram` persistence format: `content` is encoded
/// directly (synthesized Codable), one case per diagram kind with its own configuration.
@Suite("Generated Diagram Codable")
struct GeneratedDiagramCodableTests {

    private func roundTrip(_ diagram: GeneratedDiagram) throws -> GeneratedDiagram {
        let data = try JSONEncoder().encode(diagram)
        return try JSONDecoder().decode(GeneratedDiagram.self, from: data)
    }

    @Test func classDiagramRoundTripsWithConfiguration() throws {
        var config = ClassDiagramConfiguration()
        config.showProperties = false
        config.grouping = .directory
        config.minimumAccessLevel = .public

        var diagram = GeneratedDiagram(name: "C", content: .classDiagram(config), codebaseID: UUID())
        diagram.nodePositions["A"] = .init(x: 12, y: 34)
        diagram.canvasScale = 1.5

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.type == .classDiagram)
        #expect(decoded.classConfiguration?.grouping == .directory)
        #expect(decoded.classConfiguration?.minimumAccessLevel == .public)
    }

    @Test func sequenceDiagramRoundTripsWithConfiguration() throws {
        let config = SequenceDiagramConfiguration(
            entryTypeName: "Login", entryMethodName: "run",
            maxDepth: 7, typeMapping: ["P": "Impl"]
        )
        let diagram = GeneratedDiagram(name: "S", content: .sequenceDiagram(config), codebaseID: UUID())

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.type == .sequenceDiagram)
        #expect(decoded.sequenceConfiguration == config)
    }

    @Test func configurationlessKindsRoundTrip() throws {
        for content in [GeneratedDiagram.Content.packageDiagram, .moduleCoupling, .hotspot] {
            let diagram = GeneratedDiagram(name: "X", content: content, codebaseID: UUID())
            let decoded = try roundTrip(diagram)
            #expect(decoded == diagram)
            #expect(decoded.classConfiguration == nil)
            #expect(decoded.sequenceConfiguration == nil)
        }
    }

    @Test func cycleDiagramRoundTripsWithReference() throws {
        let reference = CycleDiagramReference(scope: "modules", members: ["ModuleA", "ModuleB"])
        let diagram = GeneratedDiagram(name: "Cyc", content: .cycleDiagram(reference), codebaseID: UUID())

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.type == .cycleDiagram)
        #expect(decoded.cycleDiagramReference == reference)
    }

    @Test func stateDiagramRoundTripsWithConfiguration() throws {
        let config = StateDiagramConfiguration(typeName: "Loader", variableName: "state", maxStates: 15)
        let diagram = GeneratedDiagram(name: "St", content: .stateDiagram(config), codebaseID: UUID())

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.type == .stateDiagram)
        #expect(decoded.stateConfiguration == config)
    }

    @Test func unconfiguredStateDiagramRoundTrips() throws {
        let diagram = GeneratedDiagram(name: "St", content: .stateDiagram(nil), codebaseID: UUID())
        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.stateConfiguration == nil)
        #expect(decoded.type == .stateDiagram)
    }

    // MARK: - Filter

    @Test func classDiagramFilterRoundTrips() throws {
        var config = ClassDiagramConfiguration()
        config.filter = AcaiQuality.Selector(typeGlob: "*Repository")
        let diagram = GeneratedDiagram(name: "C", content: .classDiagram(config), codebaseID: UUID())

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.classConfiguration?.filter == config.filter)
    }

    @Test func sequenceDiagramFilterRoundTrips() throws {
        var config = SequenceDiagramConfiguration(entryTypeName: "Login", entryMethodName: "run")
        config.filter = AcaiQuality.Selector(module: "UI")
        let diagram = GeneratedDiagram(name: "S", content: .sequenceDiagram(config), codebaseID: UUID())

        let decoded = try roundTrip(diagram)
        #expect(decoded == diagram)
        #expect(decoded.sequenceConfiguration?.filter == config.filter)
    }

    /// Already-persisted JSON, written before `filter` existed on `ClassDiagramConfiguration`,
    /// decodes gracefully: the missing key defaults to `nil` rather than throwing.
    @Test func classDiagramConfigurationDecodesGracefullyWithoutFilterKey() throws {
        var diagram = GeneratedDiagram(name: "C", content: .classDiagram(.init()), codebaseID: UUID())
        diagram.classConfiguration?.filter = AcaiQuality.Selector(typeGlob: "*")
        let data = try JSONEncoder().encode(diagram)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var content = try #require(json["content"] as? [String: Any])
        var classDiagram = try #require(content["classDiagram"] as? [String: Any])
        var configuration = try #require(classDiagram["_0"] as? [String: Any])
        configuration.removeValue(forKey: "filter")
        classDiagram["_0"] = configuration
        content["classDiagram"] = classDiagram
        json["content"] = content
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GeneratedDiagram.self, from: strippedData)
        #expect(decoded.classConfiguration?.filter == nil)
    }
}
