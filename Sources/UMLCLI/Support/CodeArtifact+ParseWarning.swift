import Foundation
import UMLCore

extension CodeArtifact {
    /// Prints the concrete parse problems to stderr when any source file failed to parse
    /// cleanly, so a partial diagram isn't mistaken for a complete one. Writes to stderr to
    /// keep piped stdout (DOT/JSON) clean.
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
