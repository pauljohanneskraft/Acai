import AcaiCore
import AcaiLibrary

/// One side of a `diff`: a stored artifact reference, or a source directory to analyze.
struct DiffSide: Sendable {
    let ref: String?
    let source: String?
    let language: [LanguageOption]
    let generated: GeneratedScope

    func artifact(sharing parses: SharedParses) async throws -> CodeArtifact {
        let artifact = try await ArtifactSource.resolve(
            from: ref, source: source, language: language, service: AnalysisService.standard.sharing(parses))
        return generated.applied(to: artifact)
    }
}

/// Both sides of a `diff`, resolved concurrently, parsing a file both sides hold unchanged only once.
struct DiffSides: Sendable {
    typealias Load = @Sendable (DiffSide, SharedParses) async throws -> CodeArtifact

    let old: DiffSide
    let new: DiffSide
    let load: Load

    init(old: DiffSide, new: DiffSide, load: @escaping Load = { try await $0.artifact(sharing: $1) }) {
        self.old = old
        self.new = new
        self.load = load
    }

    func resolved() async throws -> (old: CodeArtifact, new: CodeArtifact) {
        let parses = SharedParses()
        async let oldArtifact = load(old, parses)
        async let newArtifact = load(new, parses)
        return (old: try await oldArtifact, new: try await newArtifact)
    }
}
