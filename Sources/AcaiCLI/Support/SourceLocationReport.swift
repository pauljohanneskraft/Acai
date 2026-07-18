import AcaiCore

extension SourceLocation {
    /// The `file:line` jump target a human report prints for this location.
    var jumpTarget: String { "\(filePath):\(line)" }
}

extension Optional where Wrapped == SourceLocation {
    /// A trailing `  file:line` fragment for a human report row, or empty when the location is
    /// unknown. Keeps the "append the jump target if we have one" rendering in one place.
    var suffix: String {
        map { "  \($0.jumpTarget)" } ?? ""
    }
}
