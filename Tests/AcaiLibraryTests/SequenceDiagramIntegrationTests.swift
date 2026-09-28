import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// End-to-end sequence-diagram generation over a real parse of a real directory: `AnalysisService`
/// discovers and parses `Fixtures/SequenceIntegration`, then call graphs are traced from real entry
/// points. This is the "the parsers' `callSites` line up with what the generator expects" check the
/// hand-built-artifact tests can't give.
///
/// The fixture carries the receiver shapes the generator has to resolve — a stored property, a
/// method parameter, a typed local, an array of existentials and an existential property — rather
/// than being this repository's own `Sources/`, whose size dominated the test target's runtime and
/// whose content changed with every edit.
@Suite("Sequence Diagram Integration (parsed fixture)", .timeLimit(.minutes(1)))
struct SequenceDiagramIntegrationTests {

    /// Parse the fixture once and share across tests (parsing is the expensive part). A `Task`
    /// memoizes its result after the first `await` — every caller after that gets the same cached
    /// artifact or the same rethrown failure, so every test fails with the *original* error instead
    /// of confusing empty-artifact asserts.
    private static let analysisTask = Task { () throws -> CodeArtifact in
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("SequenceIntegration")
        return try await AnalysisService.standard.analyzeProject(at: fixture, allowedLanguages: [])
    }

    private static func artifact() async throws -> CodeArtifact {
        try await analysisTask.value
    }

    @Test("A known concrete-receiver call appears as a cross-participant message")
    func knownEntryPointTracesCrossTypeCall() async throws {
        // `ScreenModel.persistChanges` calls `store.save()` through the explicitly-typed
        // `store: DocumentStore` property.
        let diagram = try await SequenceDiagramBuilder(
            entryPoint: ("ScreenModel", "persistChanges")
        ).build(from: Self.artifact())

        #expect(diagram.participants.map(\.name).contains("DocumentStore"))
        #expect(diagram.messages.contains {
            $0.from == "ScreenModel" && $0.to == "DocumentStore"
                && $0.label == "save" && $0.kind == .synchronous
        })
        #expect(diagram.messages.contains { $0.kind == .return && $0.to == "ScreenModel" })
    }

    @Test("typeMapping resolves an existential receiver to a concrete detector")
    func typeMappingResolvesExistentialReceiver() async throws {
        let artifact = try await Self.artifact()
        // `SpecDiscovery.discoverSpecs` dispatches through `any SpecDetector`; mapping it to the
        // concrete `FallbackSpecDetector` must redirect the lifeline and follow the concrete
        // implementation's body.
        let unmapped = SequenceDiagramBuilder(
            entryPoint: ("SpecDiscovery", "discoverSpecs")
        ).build(from: artifact)
        #expect(unmapped.participants.map(\.name).contains("any SpecDetector"))

        let mapped = SequenceDiagramBuilder(
            entryPoint: ("SpecDiscovery", "discoverSpecs"),
            typeMapping: ["any SpecDetector": "FallbackSpecDetector"]
        ).build(from: artifact)
        #expect(mapped.participants.map(\.name).contains("FallbackSpecDetector"))
        #expect(!mapped.participants.map(\.name).contains("any SpecDetector"))
        #expect(mapped.messages.contains {
            $0.from == "SpecDiscovery" && $0.to == "FallbackSpecDetector"
                && $0.label == "discoverSpecs"
        })
        // Following the concrete body is what the mapping is for, so its own calls must show up.
        #expect(mapped.messages.contains {
            $0.from == "FallbackSpecDetector" && $0.to == "ChangeLog" && $0.label == "append"
        })
    }

    @Test("Every unambiguous concrete-receiver call site is traceable from its owning method")
    func allUnambiguousCallSitesProduceCrossParticipantMessages() async throws {
        let artifact = try await Self.artifact()
        let types = artifact.types
        // Only uniquely-named types: the generator keys lookups by simple name (first wins),
        // so duplicated names would make the assertion ambiguous rather than wrong.
        var nameCounts: [String: Int] = [:]
        for type in types { nameCounts[type.name, default: 0] += 1 }
        let uniqueTypes = Dictionary(
            types.filter { nameCounts[$0.name] == 1 }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var checked = 0
        for type in uniqueTypes.values {
            var memberNameCounts: [String: Int] = [:]
            for member in type.members { memberNameCounts[member.name, default: 0] += 1 }

            for member in type.members where member.kind == .method && memberNameCounts[member.name] == 1 {
                for site in member.callSites {
                    guard let receiver = site.receiverType,
                          receiver != type.name,
                          let receiverType = uniqueTypes[receiver],
                          receiverType.members.contains(where: { $0.name == site.methodName })
                    else { continue }

                    let diagram = SequenceDiagramBuilder(entryPoint: (type.name, member.name)).build(from: artifact)
                    let found = diagram.messages.contains {
                        $0.from == type.name && $0.to == receiver && $0.label == site.methodName
                    }
                    #expect(
                        found,
                        "\(type.name).\(member.name) → \(receiver).\(site.methodName) missing from its diagram"
                    )
                    checked += 1
                }
            }
        }

        // The fixture must keep providing real cross-type call sites for this test to mean anything.
        #expect(checked >= 10, "expected ≥10 traceable call sites in the fixture, found \(checked)")
    }
}
