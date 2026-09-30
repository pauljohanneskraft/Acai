import Foundation

extension Violation {
    /// Names the breach itself, not its current measurement: a budget breach keeps its identity as
    /// the metric's value moves, so a suppression survives a reindex that changes the number.
    public var findingIdentity: String {
        let measurements: Set<String> = ["value", "before", "after"]
        let qualifiers = detail
            .filter { !measurements.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        return ([ruleKind, subject] + qualifiers).joined(separator: "-")
    }
}
