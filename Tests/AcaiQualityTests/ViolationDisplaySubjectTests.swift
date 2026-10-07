import Testing
import AcaiCore
@testable import AcaiQuality

@Suite("Violation display subject")
struct ViolationDisplaySubjectTests {
    private let names: TypeDisplayNames = {
        let types = [("A", "Sources/Core/A.swift"), ("B", "Sources/Core/B.swift"), ("B", "Sources/App/B.swift")]
            .map { name, path in
                TypeDeclaration(
                    id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal,
                    location: SourceLocation(filePath: path, line: 1, column: 1))
            }
        return CodeArtifact(metadata: .init(sourceLanguage: .init(rawValue: "fixture")), types: types)
            .scopingTypeIDs(modules: ModuleMap(roots: [], filePaths: []))
            .typeDisplayNames
    }()

    @Test(
        "Each type id in a subject is named for display; modules and the raw subject stay as they were",
        arguments: [
            ("Core.A", "A"),
            ("Core.A→Core.B", "A→Core.B"),
            ("Core.A,App.B,Core.A", "A,App.B,A"),
            ("Core", "Core")
        ])
    func namesEachID(subject: String, expected: String) {
        let violation = Violation(ruleKind: "budget", message: "", subject: subject)
        #expect(violation.displaySubject(names) == expected)
        #expect(violation.subject == subject)
    }
}
