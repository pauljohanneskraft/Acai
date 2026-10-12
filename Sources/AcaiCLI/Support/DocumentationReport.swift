import Foundation

extension Optional where Wrapped == String {
    /// Documentation rendered as comment lines under the declaration it belongs to, or no lines at
    /// all when there is none — an undocumented declaration reports nothing rather than a
    /// placeholder. Prose the author wrote over several lines keeps its line breaks.
    func documentationLines(indent: String) -> [String] {
        guard let prose = self?.trimmingCharacters(in: .whitespacesAndNewlines), !prose.isEmpty else { return [] }
        return prose.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? "\(indent)//" : "\(indent)// \(text)"
        }
    }
}
