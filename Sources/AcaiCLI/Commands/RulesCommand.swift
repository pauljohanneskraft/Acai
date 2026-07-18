import ArgumentParser
import Foundation
import AcaiQuality
import AcaiLibrary

extension AcaiCommand {
    /// Authoring helpers for the declarative code-quality rules file consumed by `acai quality`.
    struct Rules: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rules",
            abstract: "Author and manage the code-quality rules file",
            subcommands: [Init.self]
        )

        /// Generates a candidate `quality.yml` inferred from the current graph.
        struct Init: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate a candidate quality.yml from the current graph",
                discussion: """
                Infers a draft rules file — the module-cycle invariant plus budgets seeded from the \
                current worst-case metrics — so adopting `acai quality` is "review and edit a draft" \
                rather than "author from a blank page". Review and tighten the thresholds before \
                committing.

                  acai rules init --source ./ --output quality.yml
                """
            )

            @OptionGroup var artifactSource: ArtifactSource

            @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
            var output: String?

            mutating func validate() throws {
                try artifactSource.validate()
            }

            mutating func run() throws {
                let artifact = try artifactSource.resolve()
                let graph = GraphView(
                    artifact: artifact,
                    languageResolver: artifact.standardLanguageResolver)
                try StarterQualityRules(graph: graph).yaml.writeOutput(to: output, label: "rules")
            }
        }
    }
}
