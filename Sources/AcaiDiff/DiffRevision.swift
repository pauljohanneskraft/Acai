import AcaiCore

/// One side of a diff with its metrics computed, so a caller can prepare both sides concurrently.
public struct DiffRevision: Sendable {
    public let artifact: CodeArtifact
    let metrics: CodeMetrics

    public init(_ artifact: CodeArtifact) {
        self.artifact = artifact
        self.metrics = artifact.computeMetrics()
    }
}
