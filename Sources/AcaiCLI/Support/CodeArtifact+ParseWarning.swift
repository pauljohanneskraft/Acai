import Foundation
import AcaiCore

extension CodeArtifact {
    /// Prints parse problems to stderr, keeping piped stdout (DOT/JSON) clean.
    func warnIfParseErrors() {
        let diagnostics = metadata.parseDiagnostics
        guard !diagnostics.isEmpty else { return }

        var lines = ["Warning: \(diagnostics.count) syntax issue(s) found; output may be incomplete."]
        for diagnostic in diagnostics {
            let loc = diagnostic.location
            let position = "\(loc.filePath):\(loc.line):\(loc.column)"
            lines.append("  \(position): \(diagnostic.kind.rawValue): \(diagnostic.message)")
        }
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
