#if os(macOS)
import ArgumentParser
import Foundation
import AcaiDiagram
import AcaiLibrary
import AcaiQuality
import AcaiRender

extension AcaiCommand {
    /// macOS-only, like `image`: the embedded diagrams render through SwiftUI's `ImageRenderer`.
    struct Atlas: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "atlas",
            abstract: "Bundle a codebase's diagrams, statistics and findings into one PDF (macOS only)",
            discussion: """
            The same document format as the app's Codebase Atlas export: a title page, one page per \
            diagram, the statistics the codebase detail pane shows, and every quality violation, \
            dead-code candidate and parse diagnostic. The diagram section is the default class \
            diagram, package graph and call graph.

              acai atlas --source ./ --output atlas.pdf
              acai atlas --source ./ --output atlas.pdf --rules quality.yml --theme dark
            """
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Output PDF file path.")
        var output: String

        @Option(name: .long, help: ArgumentHelp(
            "Name for the title page. Defaults to the analyzed directory's name."))
        var name: String?

        @Option(name: .long, help: ArgumentHelp(
            "Path to the YAML rules file the findings section is judged by."
            + " Defaults to the built-in curated smell budgets."))
        var rules: String?

        @Option(name: .long, help: "Output resolution scale factor for the embedded diagrams.")
        var scale: Double = 2

        @Option(name: .long, help: "Colour theme for the embedded diagrams: light or dark.")
        var theme: ThemeOption = .light

        @Option(name: .long, help: "Maximum node count before a graph diagram's page reports it could not render.")
        var maxNodes: Int = DiagramNodeLimit.defaultMaximum

        mutating func validate() throws {
            try artifactSource.validate()
            try DiagramLimits().validate(maxNodes: maxNodes)
            guard scale > 0 else {
                throw ValidationError("--scale must be greater than 0.")
            }
        }

        mutating func run() async throws {
            let artifact = try await artifactSource.resolve()
            let ruleSet = try rules.map { try QualityRules.load(contentsOf: $0) } ?? QualityRules.defaultQuality
            guard ruleSet.movements.isEmpty else {
                throw ValidationError(
                    "The rules file declares \(ruleSet.movements.count) movement rule(s), which the atlas"
                    + " cannot evaluate without a baseline. Use `acai quality --baseline` for those."
                )
            }
            let languages = artifact.standardLanguageResolver

            let analysis = AtlasAnalysis(artifact: artifact, rules: ruleSet, languages: languages)
            let diagrams = await AtlasDiagramSet(
                scale: scale, palette: theme == .dark ? .dark : .light,
                languages: languages, maxNodes: maxNodes
            ).pages(for: artifact)
            warnAboutUnrenderedDiagrams(in: diagrams)

            let document = AtlasDocument(
                codebaseName: codebaseName, diagrams: diagrams,
                metrics: analysis.metrics, findings: analysis.findings)
            try document.pdfData().write(to: URL(fileURLWithPath: output), options: .atomic)
            print("Wrote atlas to \(output)")
        }

        /// Otherwise the reason appears only inside the PDF.
        private func warnAboutUnrenderedDiagrams(in pages: [AtlasDiagramPage]) {
            for page in pages {
                guard let reason = page.image.failureReason else { continue }
                "Warning: the \(page.name) page could not be rendered: \(reason)".writeLineToStandardError()
            }
        }

        private var codebaseName: String {
            if let name { return name }
            if let source = artifactSource.source {
                return URL(fileURLWithPath: source).standardizedFileURL.lastPathComponent
            }
            return artifactSource.from ?? "Codebase"
        }
    }
}
#endif
