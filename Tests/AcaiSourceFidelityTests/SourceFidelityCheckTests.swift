import Testing
import AcaiCore

/// A check that cannot fail proves nothing, so each one is shown failing on an artifact broken in
/// exactly the way it exists to catch. The language is one no difference is declared for, which is
/// also what holds these cases to the strict reading.
@Suite("Each fidelity check fails on a broken artifact")
struct SourceFidelityCheckTests {

    /// `Money` starts at column 8 of line 1 and `currency` at column 9 of line 2.
    private let source = """
    struct Money {
        let currency: Text
    }
    """

    private var baseline: CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "fixture"), filePaths: ["Money.fixture"]),
            types: [
                TypeDeclaration(
                    id: "Money", name: "Money", qualifiedName: "Money", kind: .struct, accessLevel: .internal,
                    members: [
                        Member(
                            name: "currency", kind: .property, accessLevel: .internal,
                            type: TypeReference(name: "Text"),
                            location: .init(filePath: "Money.fixture", line: 2, column: 9, endLine: 2)
                        )
                    ],
                    location: .init(filePath: "Money.fixture", line: 1, column: 8, endLine: 3)
                )
            ]
        )
    }

    @Test("the unbroken artifact has nothing to report")
    func baselineAgreesWithItsSource() {
        #expect(violations(of: baseline).isEmpty, "\(violations(of: baseline))")
    }

    @Test("a column that lands on whitespace is caught")
    func columnOnWhitespace() {
        var artifact = baseline
        artifact.types[0].members[0].location?.column = 8
        expect(.location, "is whitespace on line 2", in: artifact)
    }

    @Test("a column past the end of its line is caught")
    func columnPastEndOfLine() {
        var artifact = baseline
        artifact.types[0].members[0].location?.column = 99
        expect(.location, "is past the end of line 2", in: artifact)
    }

    @Test("a line outside the file is caught")
    func lineOutsideFile() {
        var artifact = baseline
        artifact.types[0].location?.line = 99
        expect(.location, "outside the 3-line file", in: artifact)
    }

    @Test("an endLine before its line is caught")
    func invertedEndLine() {
        var artifact = baseline
        artifact.types[0].location?.endLine = 0
        expect(.location, "endLine 0 is before line 1", in: artifact)
    }

    @Test("a name absent from its own span is caught")
    func nameAbsentFromSpan() {
        var artifact = baseline
        artifact.types[0].members[0].name = "price"
        expect(.location, "the name 'price' does not occur", in: artifact)
    }

    @Test("a second type on the same id is caught")
    func duplicateTypeID() {
        var artifact = baseline
        artifact.types.append(artifact.types[0])
        expect(.identity, "a second type declares the same id", in: artifact)
    }

    @Test("a type the source never spells is caught")
    func typeAbsentFromSource() {
        var artifact = baseline
        artifact.types[0].members[0].type = TypeReference(name: "Number")
        expect(.type, "'Number' does not occur in its own source span", in: artifact)
    }

    @Test("a type cut short in the artifact is caught", arguments: [
        ("Text?", "'?'"), ("Text*", "'*'"), ("Text<Int>", "'<'"), ("Text[4]", "'['")
    ])
    func typeCutShort(written: String, following: String) {
        let check = SourceFidelityCheck(
            text: SourceText(source.replacingOccurrences(of: "Text", with: written)),
            artifact: baseline,
            difference: DeclaredLanguageDifference()
        )
        let violations = check.violations
        #expect(
            violations.contains { $0.rule == .type && $0.detail.contains("is followed by \(following)") },
            "\(written) was accepted as `Text`: \(violations)"
        )
    }

    private func violations(of artifact: CodeArtifact) -> [FidelityViolation] {
        SourceFidelityCheck(
            text: SourceText(source), artifact: artifact, difference: DeclaredLanguageDifference()
        ).violations
    }

    private func expect(
        _ rule: FidelityViolation.Rule, _ detail: String, in artifact: CodeArtifact,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        let violations = self.violations(of: artifact)
        #expect(
            violations.contains { $0.rule == rule && $0.detail.contains(detail) },
            "no \(rule.rawValue) violation mentioning '\(detail)': \(violations)",
            sourceLocation: sourceLocation
        )
    }
}
