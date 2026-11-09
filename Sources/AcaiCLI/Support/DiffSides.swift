import AcaiCore

/// One side of a `diff`: a stored artifact reference, or a source directory to analyze.
struct DiffSide: Sendable {
    let ref: String?
    let source: String?
    let language: [LanguageOption]
    let generated: GeneratedScope

    func artifact() async throws -> CodeArtifact {
        let artifact = try await ArtifactSource.resolve(from: ref, source: source, language: language)
        return generated.applied(to: artifact)
    }
}

/// Both sides of a `diff`, resolved concurrently — `--source-old`/`--source-new` then costs about
/// one `analyze` of the larger side rather than the two in series it used to.
struct DiffSides: Sendable {
    typealias Load = @Sendable (DiffSide) async throws -> CodeArtifact

    let old: DiffSide
    let new: DiffSide
    /// Substituted in tests to observe that the two sides really do overlap.
    let load: Load

    init(old: DiffSide, new: DiffSide, load: @escaping Load = { try await $0.artifact() }) {
        self.old = old
        self.new = new
        self.load = load
    }

    func resolved() async throws -> (old: CodeArtifact, new: CodeArtifact) {
        async let oldArtifact = load(old)
        async let newArtifact = load(new)
        return (old: try await oldArtifact, new: try await newArtifact)
    }
}
