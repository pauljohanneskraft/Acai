import Foundation
import Testing
import AcaiCore
@testable import AcaiCLI

@Suite("CLI: diff side resolution", .timeLimit(.minutes(1)))
struct DiffSidesTests {

    /// Records the order the two sides enter and leave their load. Each side waits — by yielding,
    /// never by sleeping — until the other has entered, so a concurrent implementation interleaves
    /// at once and a serial one spins out its bounded budget and reports no overlap instead of
    /// deadlocking.
    private actor OverlapWitness {
        private var exited = false
        private(set) var entered = 0
        private(set) var overlapped = false

        func enter() {
            entered += 1
            if entered > 1 && !exited { overlapped = true }
        }

        func exit() { exited = true }
    }

    private func side(_ source: String) -> DiffSide {
        DiffSide(ref: nil, source: source, language: [], generated: GeneratedScope(includeGenerated: true))
    }

    private func artifact(_ name: String) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
                     types: [TypeDeclaration(id: name, name: name, qualifiedName: name,
                                             kind: .class, accessLevel: .internal)])
    }

    @Test func resolvesBothSidesConcurrently() async throws {
        let witness = OverlapWitness()
        let sides = DiffSides(old: side("./before"), new: side("./after")) { requested in
            await witness.enter()
            var spins = 0
            while await witness.entered < 2, spins < 1_000 {
                spins += 1
                await Task.yield()
            }
            await witness.exit()
            return self.artifact(requested.source ?? "")
        }

        let resolved = try await sides.resolved()

        #expect(await witness.overlapped, "the two sides did not overlap")
        #expect(resolved.old.types.first?.id == "./before")
        #expect(resolved.new.types.first?.id == "./after")
    }

    private struct SideFailure: Error {}

    @Test func propagatesAFailureFromEitherSide() async {
        let sides = DiffSides(old: side("./before"), new: side("./after")) { requested in
            guard requested.source == "./before" else { return self.artifact("ok") }
            throw SideFailure()
        }

        await #expect(throws: SideFailure.self) { _ = try await sides.resolved() }
    }
}
