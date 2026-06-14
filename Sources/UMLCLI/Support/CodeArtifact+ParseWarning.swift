import Foundation
import UMLCore

extension CodeArtifact {
    /// Prints a warning to stderr when any source file failed to parse cleanly, so a partial
    /// diagram isn't mistaken for a complete one. Writes to stderr to keep piped stdout (DOT/JSON) clean.
    func warnIfParseErrors() {
        guard metadata.hasParseErrors else { return }
        FileHandle.standardError.write(Data(
            "Warning: some files had syntax errors; output may be incomplete.\n".utf8
        ))
    }
}
