/// The findings a Compare panel's two revisions disagree on, keyed by rule/subject identity and
/// file — not `Finding.id`, which embeds an array offset and shifts whenever an unrelated finding
/// earlier in the same file is added or removed, so it isn't stable enough to diff by.
struct CompareFindingsDelta {
    let oldFindings: [Finding]
    let newFindings: [Finding]

    private struct Key: Hashable {
        let kind: Finding.Kind
        let title: String
        let filePath: String?
    }

    private func key(_ finding: Finding) -> Key {
        Key(kind: finding.kind, title: finding.title, filePath: finding.location?.filePath)
    }

    /// Findings present in `newFindings` with no matching key in `oldFindings` — genuinely new,
    /// not just the same finding shifted to a different line.
    var added: [Finding] {
        let oldKeys = Set(oldFindings.map(key))
        return newFindings.filter { !oldKeys.contains(key($0)) }
    }
}
