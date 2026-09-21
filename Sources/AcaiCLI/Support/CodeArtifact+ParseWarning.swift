import AcaiCore

extension CodeArtifact {
    /// Prints a one-line trust warning to stderr when this artifact's parse health falls below
    /// `HealthCheck.trustThreshold`, keeping piped stdout (DOT/JSON) clean. Points at
    /// `acai analyze --health` for the full diagnostic list rather than dumping it here.
    func warnIfLowHealth() {
        let summary = HealthCheck(artifact: self).summary
        guard summary.score < HealthCheck.trustThreshold else { return }
        let percent = Int((summary.score * 100).rounded())
        ("Warning: parse health is \(percent)% (\(summary.diagnosticCount) diagnostic(s)); "
            + "run `acai analyze --health` for the list.").writeLineToStandardError()
    }
}
