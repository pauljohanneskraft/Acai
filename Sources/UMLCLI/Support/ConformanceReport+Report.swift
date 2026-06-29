import UMLConformance

extension ConformanceReport {
    /// A compiler-style, CI-grep-friendly rendering: one `file:line: ruleKind: message` per
    /// violation (location omitted when a violation is module-level), with a summary footer.
    func humanReport() -> String {
        guard !violations.isEmpty else {
            return "Conformance OK — \(checkedRuleCount) rule(s) checked, no violations.\n"
        }
        var lines = violations.map { violation -> String in
            let prefix = violation.source.map { "\($0.filePath):\($0.line): " } ?? ""
            return "\(prefix)\(violation.ruleKind): \(violation.message)"
        }
        lines.append("")
        lines.append("\(violations.count) violation(s) across \(checkedRuleCount) rule(s).")
        return lines.joined(separator: "\n") + "\n"
    }
}
