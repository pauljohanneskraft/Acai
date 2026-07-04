import ArgumentParser
import Foundation
import UMLConformance
import UMLLibrary

extension UMLCommand {
    /// Authoring helpers for the declarative architecture rules file consumed by `uml check`.
    struct Rules: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rules",
            abstract: "Author and manage the architecture rules file",
            subcommands: [Init.self]
        )

        /// Generates a candidate `architecture.yml` inferred from the current graph.
        struct Init: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Generate a candidate architecture.yml from the current graph",
                discussion: """
                Infers a draft rules file — the module-cycle invariant plus budgets seeded from the \
                current worst-case metrics — so adopting `uml check` is "review and edit a draft" \
                rather than "author from a blank page". Review and tighten the thresholds before \
                committing.

                  uml rules init --source ./ --output architecture.yml
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
                    annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes)
                try StarterArchitectureRules(graph: graph).yaml.writeOutput(to: output, label: "rules")
            }
        }
    }
}
