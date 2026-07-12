import ArgumentParser
import UMLCore
import UMLLibrary

/// Shared `--include-generated` flag for the analysis commands (`metrics`, `analyze`, `callgraph`,
/// `inspect`, `impact`). Machine-generated types are **excluded by default** so a report reflects
/// only hand-written code — matching the app's statistics pane and the MCP tools' `includeGenerated`
/// default. Pass `--include-generated` to analyse everything.
///
/// (These commands don't evaluate a rules file — only `uml quality` does, where the same setting
/// lives as `includeGeneratedTypes` — so the scope here is an explicit flag rather than a file.)
struct GeneratedScopeOption: ParsableArguments {
    @Flag(name: .customLong("include-generated"),
          help: "Include machine-generated types in the analysis (default: they are excluded).")
    var includeGenerated = false

    /// Returns `artifact` with each language's generated types dropped, unless `--include-generated`.
    func applied(to artifact: CodeArtifact) -> CodeArtifact {
        includeGenerated
            ? artifact
            : artifact.filteringGeneratedTypes(using: artifact.standardLanguageResolver)
    }
}
