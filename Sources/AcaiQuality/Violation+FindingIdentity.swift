import Foundation

extension Violation {
    /// Names the breach itself, not its current measurement or evidence, so a suppression survives a
    /// reindex that changes a budget's value or moves a cycle witness's line.
    public var findingIdentity: String {
        let evidence: Set<String> = ["value", "before", "after", "witnesses"]
        let qualifiers = detail
            .filter { !evidence.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return ([ruleKind, subject] + qualifiers).joined(separator: "-")
    }
}
