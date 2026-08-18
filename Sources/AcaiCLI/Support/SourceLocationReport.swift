import AcaiCore

extension SourceLocation {
    var jumpTarget: String { "\(filePath):\(line)" }
}

extension Optional where Wrapped == SourceLocation {
    var suffix: String {
        map { "  \($0.jumpTarget)" } ?? ""
    }
}
