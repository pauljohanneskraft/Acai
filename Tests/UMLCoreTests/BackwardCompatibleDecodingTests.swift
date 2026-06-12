import Testing
import Foundation
@testable import UMLCore

/// Ensures analyses stored before the new fields existed still decode (with defaults),
/// so `uml list` / `diagram --from <name>` don't break on older `~/.uml/analysis` data.
@Suite("Core: Backward-Compatible Decoding")
struct BackwardCompatibleDecodingTests {

    @Test func legacyArtifactWithoutNewKeysDecodes() throws {
        // No `globalVariables`, no `metadata.hasParseErrors`, no `associatedTypes`.
        let legacy = """
        {
          "metadata": { "sourceLanguage": "swift", "filePaths": ["A.swift"] },
          "types": [
            {
              "id": "A", "name": "A", "qualifiedName": "A", "kind": "class"
            }
          ],
          "relationships": [],
          "freestandingFunctions": []
        }
        """
        let data = Data(legacy.utf8)
        let artifact = try JSONDecoder().decode(CodeArtifact.self, from: data)

        #expect(artifact.globalVariables.isEmpty)
        #expect(artifact.metadata.hasParseErrors == false)
        #expect(artifact.types.count == 1)
        #expect(artifact.types[0].associatedTypes.isEmpty)
        #expect(artifact.types[0].name == "A")
    }

    @Test func roundTripPreservesNewFields() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, hasParseErrors: true),
            types: [TypeDeclaration(
                id: "P", name: "P", qualifiedName: "P", kind: .protocol,
                associatedTypes: [GenericParameter(name: "Item")])],
            globalVariables: [Member(name: "shared", kind: .property)]
        )
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(CodeArtifact.self, from: data)
        #expect(decoded == artifact)
        #expect(decoded.metadata.hasParseErrors == true)
        #expect(decoded.globalVariables.map(\.name) == ["shared"])
        #expect(decoded.types[0].associatedTypes.map(\.name) == ["Item"])
    }

    @Test func legacyMemberWithoutAssignmentKeysDecodes() throws {
        // No `assignments`, no `initialValue`, no `callSites` (predates all three).
        let legacy = """
        {
          "name": "load", "kind": "method", "modifiers": [], "parameters": [],
          "genericParameters": [], "isComputed": false, "annotations": []
        }
        """
        let member = try JSONDecoder().decode(Member.self, from: Data(legacy.utf8))
        #expect(member.name == "load")
        #expect(member.callSites.isEmpty)
        #expect(member.assignments.isEmpty)
        #expect(member.initialValue == nil)
    }

    @Test func memberRoundTripPreservesAssignments() throws {
        let member = Member(
            name: "load",
            kind: .method,
            assignments: [VariableAssignment(
                targetName: "state",
                op: .assign,
                value: .init(kind: .enumCase, text: "loading", receiverTypeName: "State"),
                location: SourceLocation(filePath: "A.swift", line: 3, column: 9)
            )],
            initialValue: .init(kind: .booleanLiteral, text: "true")
        )
        let data = try JSONEncoder().encode(member)
        let decoded = try JSONDecoder().decode(Member.self, from: data)
        #expect(decoded == member)
        #expect(decoded.assignments[0].value.kind == .enumCase)
        #expect(decoded.initialValue?.text == "true")
    }
}
