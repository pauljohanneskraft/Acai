import ArgumentParser
import AcaiCore
import AcaiLibrary

/// Shared `--include-generated` flag for the analysis commands. Machine-generated types are
/// **excluded by default** so a report reflects only hand-written code; pass the flag to analyse
/// everything.
struct GeneratedScopeOption: ParsableArguments {
    @Flag(name: .customLong("include-generated"),
          help: "Include machine-generated types in the analysis (default: they are excluded).")
    var includeGenerated = false

    func applied(to artifact: CodeArtifact) -> CodeArtifact {
        includeGenerated
            ? artifact
            : artifact.filteringGeneratedTypes(using: artifact.standardLanguageResolver)
    }
}
