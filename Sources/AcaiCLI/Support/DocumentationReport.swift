extension Optional where Wrapped == String {
    /// Documentation rendered as comment lines under the declaration it belongs to, or no lines at
    /// all when there is none — an undocumented declaration reports nothing rather than a
    /// placeholder. Prose written over several lines keeps its breaks and its own indentation, so a
    /// code sample inside it still reads as one.
    func documentationLines(indent: String) -> [String] {
        guard let prose = self, !prose.isEmpty else { return [] }
        return prose.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "\(indent)//" : "\(indent)// \(line)"
        }
    }
}
