import Testing
import AcaiCore
@testable import AcaiDiff

/// Free functions and module-scope variables are where a C or Python codebase keeps most of its
/// code, so a diff that only compares types reports almost nothing for them.
@Suite("Diff: free functions and globals")
struct FreeDeclarationDiffTests {

    private func artifact(functions: [Member] = [], globals: [Member] = []) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            freestandingFunctions: functions,
            globalVariables: globals
        ).enriched()
    }

    private func function(_ name: String, returning type: String = "Void") -> Member {
        Member(name: name, kind: .method, accessLevel: .public, type: TypeReference(name: type))
    }

    private func global(_ name: String, of type: String) -> Member {
        Member(name: name, kind: .property, accessLevel: .public, type: TypeReference(name: type))
    }

    @Test func reportsAddedAndRemovedFreeFunctions() {
        let old = artifact(functions: [function("parse"), function("render")])
        let new = artifact(functions: [function("parse"), function("emit")])
        let diff = ArtifactDiffer().diff(old: old, new: new)

        #expect(!diff.isEmpty)
        #expect(diff.addedFunctions.contains { $0.contains("emit") })
        #expect(diff.removedFunctions.contains { $0.contains("render") })
        #expect(diff.changedFunctions.isEmpty)
    }

    @Test func pairsARetypedFreeFunctionAsOneChange() throws {
        let old = artifact(functions: [function("parse", returning: "Bool")])
        let new = artifact(functions: [function("parse", returning: "Int")])
        let diff = ArtifactDiffer().diff(old: old, new: new)

        #expect(diff.addedFunctions.isEmpty)
        #expect(diff.removedFunctions.isEmpty)
        let change = try #require(diff.changedFunctions.first)
        #expect(change.name == "parse")
        #expect(change.before.contains("Bool"))
        #expect(change.after.contains("Int"))
    }

    @Test func reportsGlobalsSeparatelyFromFunctions() {
        let old = artifact(globals: [global("version", of: "String")])
        let new = artifact(globals: [global("version", of: "String"), global("retries", of: "Int")])
        let diff = ArtifactDiffer().diff(old: old, new: new)

        #expect(diff.addedGlobals.contains { $0.contains("retries") })
        #expect(diff.addedFunctions.isEmpty)
    }

    @Test func anArtifactWithOnlyFreeFunctionsDiffsAgainstItselfAsEmpty() {
        let only = artifact(functions: [function("parse")], globals: [global("version", of: "String")])
        #expect(ArtifactDiffer().diff(old: only, new: only).isEmpty)
    }

    @Test func theUnionKeepsBothSidesFreeDeclarations() {
        let old = artifact(functions: [function("render")], globals: [global("legacy", of: "Bool")])
        let new = artifact(functions: [function("emit")], globals: [global("version", of: "String")])
        let union = ArtifactDiffer().unionArtifact(old: old, new: new)

        #expect(union.freestandingFunctions.map(\.name).sorted() == ["emit", "render"])
        #expect(union.globalVariables.map(\.name).sorted() == ["legacy", "version"])
    }
}
