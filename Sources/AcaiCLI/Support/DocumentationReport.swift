extension Optional where Wrapped == String {
    /// Comment lines under a declaration, keeping the prose's own line breaks; none when undocumented.
    func documentationLines(indent: String) -> [String] {
        guard let prose = self, !prose.isEmpty else { return [] }
        return prose.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "\(indent)//" : "\(indent)// \(line)"
        }
    }
}
