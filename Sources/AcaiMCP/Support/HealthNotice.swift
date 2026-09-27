import AcaiCore

extension HealthCheck.Summary {
    /// A one-line notice for a text-only tool result (`acai_diagram`, which renders diagram source
    /// rather than JSON, so it has no `health` field to embed this in) when the score is below
    /// `HealthCheck.trustThreshold`; `nil` above it.
    var lowTrustNotice: String? {
        guard score < HealthCheck.trustThreshold else { return nil }
        let percent = Int((score * 100).rounded())
        return "Parse health is \(percent)% (\(diagnosticCount) diagnostic(s)); "
            + "call acai_analyze with health: true for the list."
    }
}
