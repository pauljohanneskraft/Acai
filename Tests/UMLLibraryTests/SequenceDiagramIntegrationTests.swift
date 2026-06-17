import Foundation
import Testing
import UMLCore
import UMLDiagram
@testable import UMLLibrary

/// End-to-end sequence-diagram generation over this repository's own sources: parse the real
/// codebase with `AnalysisService`, then trace call graphs from real entry points. This is the
/// "universally works" check the synthetic-fixture tests can't give — the parsers' `callSites`
/// must line up with what the generator expects.
@Suite("Sequence Diagram Integration (own sources)", .serialized)
struct SequenceDiagramIntegrationTests {

    /// Parse the repo's `Sources/` once and share across tests (parsing is the expensive part).
    /// Stored as a `Result` so an analysis failure (e.g. a CI filesystem-layout difference)
    /// fails every test with the *original* error instead of confusing empty-artifact asserts.
    private static let analysisResult = Result { () throws -> CodeArtifact in
        // Tests/UMLLibraryTests/SequenceDiagramIntegrationTests.swift → repo root is two up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = repoRoot.appendingPathComponent("Sources")
        return try AnalysisService.standard.analyzeProject(at: sources, allowedLanguages: [])
    }

    private static func artifact() throws -> CodeArtifact {
        try analysisResult.get()
    }

    @Test("A known concrete-receiver call appears as a cross-participant message")
    func knownEntryPointTracesCrossTypeCall() throws {
        // `ProjectBrowserViewModel.persistChanges` calls `store.save()` through the
        // explicitly-typed `store: ProjectStore` property.
        let diagram = try Self.artifact().sequenceDiagram(
            entryPoint: ("ProjectBrowserViewModel", "persistChanges")
        )

        #expect(diagram.participants.map(\.name).contains("ProjectStore"))
        #expect(diagram.messages.contains {
            $0.from == "ProjectBrowserViewModel" && $0.to == "ProjectStore"
                && $0.label == "save" && $0.kind == .synchronous
        })
        // Every call gets a matching return.
        #expect(diagram.messages.contains { $0.kind == .return && $0.to == "ProjectBrowserViewModel" })
    }

    @Test("typeMapping resolves an existential receiver to a concrete detector")
    func typeMappingResolvesExistentialReceiver() throws {
        let artifact = try Self.artifact()
        // `ProjectDiscovery.discoverSourceSpecs` dispatches through `any BuildSystemDetector`;
        // mapping it to the concrete `FallbackDetector` must redirect the lifeline and follow
        // the concrete implementation's body.
        let unmapped = artifact.sequenceDiagram(
            entryPoint: ("ProjectDiscovery", "discoverSourceSpecs")
        )
        #expect(unmapped.participants.map(\.name).contains("any BuildSystemDetector"))

        let mapped = artifact.sequenceDiagram(
            entryPoint: ("ProjectDiscovery", "discoverSourceSpecs"),
            typeMapping: ["any BuildSystemDetector": "FallbackDetector"]
        )
        #expect(mapped.participants.map(\.name).contains("FallbackDetector"))
        #expect(!mapped.participants.map(\.name).contains("any BuildSystemDetector"))
        #expect(mapped.messages.contains {
            $0.from == "ProjectDiscovery" && $0.to == "FallbackDetector"
                && $0.label == "discoverSourceSpecs"
        })
    }

    @Test("Every unambiguous concrete-receiver call site is traceable from its owning method")
    func allUnambiguousCallSitesProduceCrossParticipantMessages() throws {
        let artifact = try Self.artifact()
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
                    // Only calls whose receiver is another uniquely-named parsed type that
                    // actually declares the called method.
                    guard let receiver = site.receiverType,
                          receiver != type.name,
                          let receiverType = uniqueTypes[receiver],
                          receiverType.members.contains(where: { $0.name == site.methodName })
                    else { continue }

                    let diagram = artifact.sequenceDiagram(entryPoint: (type.name, member.name))
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

        // The repo must keep providing real cross-type call sites for this test to mean anything.
        #expect(checked >= 10, "expected ≥10 traceable call sites in own sources, found \(checked)")
    }
}
