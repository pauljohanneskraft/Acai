import Foundation
import Testing
import UMLDiagram
import UMLRender
@testable import UMLApp

/// Round-trip coverage for the `GeneratedDiagram` persistence format: `content` is encoded
/// directly (synthesized Codable), one case per diagram kind with its own configuration.
/// Format break 2026-06: stores written by earlier versions (flat `type`/`configuration`
/// keys) are not readable.
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
        for content in [GeneratedDiagram.Content.useCaseDiagram, .deploymentDiagram] {
            let diagram = GeneratedDiagram(name: "X", content: content, codebaseID: UUID())
            let decoded = try roundTrip(diagram)
            #expect(decoded == diagram)
            #expect(decoded.classConfiguration == nil)
            #expect(decoded.sequenceConfiguration == nil)
        }
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

    /// Pins the migration behaviour: a `.stateDiagram` persisted before the case gained its
    /// configuration payload (encoded as an empty object) must decode as "unconfigured".
    @Test func legacyConfigurationlessStateDiagramDecodes() throws {
        let codebaseID = UUID()
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy State",
          "content": { "stateDiagram": {} },
          "codebaseID": "\(codebaseID.uuidString)",
          "nodePositions": {},
          "nodeSizes": {},
          "canvasScale": 1,
          "canvasOffsetX": 0,
          "canvasOffsetY": 0,
          "createdDate": 700000000,
          "lastModified": 700000000
        }
        """
        let decoded = try JSONDecoder().decode(GeneratedDiagram.self, from: Data(legacy.utf8))
        #expect(decoded.type == .stateDiagram)
        #expect(decoded.stateConfiguration == nil)
    }
}
