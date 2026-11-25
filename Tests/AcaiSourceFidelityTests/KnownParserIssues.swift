/// Violations an open issue explains; an entry that stops matching fails the suite until it goes.
struct KnownParserIssues {

    struct Entry: Sendable {
        let subject: String
        let declaration: String
        let rule: FidelityViolation.Rule
        /// Enough detail to name the exact reference, so a sibling defect is not swallowed with it.
        let detail: String
        let issue: String

        func matches(_ violation: FidelityViolation) -> Bool {
            violation.rule == rule
                && violation.declaration == declaration
                && violation.detail.contains(detail)
        }
    }

    let entries: [Entry]

    init() {
        let nullability = "#614: the Dart signature readers fold a name's type arguments but not a `?` after them, "
            + "so a nullable parameter type reports isOptional: false"
        let arguments = "The same Dart signature readers drop a parameter type's arguments outright, so `List<T> xs` "
            + "reports `List` with none. Unfiled: #614 covers the `?`, not this, and this suite found it"
        entries = [
            Entry(
                subject: "golden/members.dart", declaration: "member Counter.withCallback",
                rule: .type, detail: "parameter 'at'", issue: nullability
            ),
            Entry(
                subject: "golden/types.dart", declaration: "member Matrix.Matrix",
                rule: .type, detail: "parameter 'values'", issue: arguments
            ),
            Entry(
                subject: "golden/types.dart", declaration: "member Matrix.compareTo",
                rule: .type, detail: "parameter 'other'", issue: arguments
            )
        ]
    }

    func entries(for subject: SourceFidelityCorpus.Subject) -> [Entry] {
        entries.filter { $0.subject == subject.label }
    }
}
