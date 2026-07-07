#if os(macOS)
import ArgumentParser
import CoreGraphics
import Foundation
import SwiftUI
import UMLDiagram
import UMLDiff
import UMLLibrary
import UMLRender

extension UMLCommand {
    /// Renders a class diagram to a PNG image using the same SwiftUI views and layout engine
    /// as the macOS app (via `UMLRender`), rather than going through DOT/Graphviz.
    ///
    /// macOS-only: image rendering relies on SwiftUI's `ImageRenderer`, which needs a GUI /
    /// window-server session. On other platforms this subcommand is not registered.
    struct Image: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Render a class diagram to a PNG image (macOS only)"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Output PNG file path.")
        var output: String

        @Option(name: .long, help: "Old side for a delta image: a source directory to analyze.")
        var sourceOld: String?

        @Option(name: .long, help: "Old side for a delta image: a stored analysis name or .json path.")
        var fromOld: String?

        @Option(name: .long, help: "Grouping strategy: none, directory, product.")
        var grouping: ClassDiagramConfiguration.Grouping = .product

        @Option(name: .long, help: ArgumentHelp(
            "Only show members (and whole types) at or above this access level:" +
            " open, public, packagePrivate, internal, protected, filePrivate, private."
        ))
        var minAccess: AccessLevel?

        @Flag(name: .long, help: "Hide type members (properties and methods).")
        var hideMembers: Bool = false

        @Option(name: .long, help: "Output resolution scale factor.")
        var scale: Double = 2

        @Option(name: .long, help: "Colour theme for the rendered image: default (light) or dark.")
        var theme: ThemeOption = .default

        /// The render palette for the selected `--theme`.
        private var palette: DiagramPalette {
            theme == .dark ? .dark : .light
        }

        @Option(name: .long, help: ArgumentHelp(
            "Render a sequence diagram traced from this entry point instead of a class diagram." +
            " Format: \"TypeName.methodName\", or \"functionName\" for a top-level function."
        ))
        var sequenceFrom: String?

        @Option(name: .long, help: ArgumentHelp(
            "Resolve an interface/protocol to a concrete type when tracing a sequence diagram." +
            " Repeat for multiple: --map Protocol=Concrete --map Other=Impl."
        ))
        var map: [String] = []

        @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
        var maxDepth: Int = 5

        @Option(name: .long, help: ArgumentHelp(
            "Render a value-flow state diagram for this variable instead of a class diagram." +
            " Format: \"TypeName.variableName\", or just \"variableName\" for a global."
        ))
        var stateFrom: String?

        @Option(name: .long, help: "Maximum number of distinct states before the analysis fails.")
        var maxStates: Int = 20

        @Flag(name: .long, help: "Render a package/module dependency diagram instead of a class diagram.")
        var package: Bool = false

        @Flag(name: .long, help: "Render a static call graph instead of a class diagram.")
        var callGraph: Bool = false

        @Option(name: .long, help: ArgumentHelp(
            "Scope the call graph to a single type or build module:"
            + " \"type:Name\" or \"module:Name\". Defaults to the whole codebase."
        ))
        var callGraphScope: String?

        @Option(name: .long, help: ArgumentHelp(
            "Focus the class diagram on a single type, showing only the subgraph around it."
            + " Pass the type name."
        ))
        var focus: String?

        @Option(name: .long, help: ArgumentHelp(
            "Maximum focus traversal depth (1 = the type plus its direct neighbours)."
            + " Omit for unlimited."
        ))
        var focusDepth: Int?

        @Option(name: .long, help: "Focus traversal direction: dependencies, dependents, both.")
        var focusDirection: FocusDirectionOption?

        @Option(name: .long, help: ArgumentHelp(
            "Restrict focus to one or more relationship kinds (e.g. inheritance)."
            + " Repeat the flag for multiple. Defaults to all kinds."
        ))
        var focusRelationship: [RelationshipKindOption] = []

        @Flag(name: .long, help: ArgumentHelp(
            "When focusing, draw only the edges actually walked, not every edge among the"
            + " selected types."
        ))
        var noFocusInterconnections: Bool = false

        mutating func validate() throws {
            try artifactSource.validate()
            let modeFlags = [sequenceFrom != nil, stateFrom != nil, package, callGraph].filter { $0 }.count
            if modeFlags > 1 {
                throw ValidationError(
                    "Specify only one of --sequence-from, --state-from, --package, or --call-graph."
                )
            }
            if callGraphScope != nil && !callGraph {
                throw ValidationError("--call-graph-scope requires --call-graph.")
            }
            try DiagramLimits().validate(maxDepth: maxDepth, maxStates: maxStates)
        }

        /// The "old" side for a delta image, when `--source-old` / `--from-old` is given.
        private func resolveOldArtifact() throws -> CodeArtifact? {
            guard fromOld != nil || sourceOld != nil else { return nil }
            return try ArtifactSource.resolve(from: fromOld, source: sourceOld, language: artifactSource.language)
        }

        mutating func run() async throws {
            let artifact = try artifactSource.resolve()
            let oldArtifact = try resolveOldArtifact()

            let data = try await renderData(artifact: artifact, old: oldArtifact)

            let outputURL = URL(fileURLWithPath: output)
            try data.write(to: outputURL, options: .atomic)
            print("Wrote image to \(output)")
        }

        /// Selects the per-kind image exporter for the requested flags and renders the PNG — a delta
        /// when an OLD revision is given, otherwise the plain diagram.
        private func renderData(artifact: CodeArtifact, old: CodeArtifact?) async throws -> Data {
            if let sequenceFrom {
                let exporter = SequenceImageExporter(
                    scale: scale, palette: palette, entryPoint: sequenceFrom, maxDepth: maxDepth, map: map)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if let stateFrom {
                let exporter = StateImageExporter(
                    scale: scale, palette: palette, variable: stateFrom, maxStates: maxStates)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if package {
                let exporter = PackageImageExporter(
                    scale: scale, palette: palette, languages: artifact.standardLanguageResolver)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if callGraph {
                let exporter = CallGraphImageExporter(
                    scale: scale, palette: palette, scope: CallGraphScopeOption(raw: callGraphScope))
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else {
                let exporter = ClassImageExporter(
                    scale: scale, palette: palette, configuration: classDiagramConfiguration(),
                    languages: artifact.standardLanguageResolver)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            }
        }

        /// The class-diagram configuration derived from the grouping/access/member/focus flags,
        /// shared by the plain and delta render paths so they honour the same options.
        private func classDiagramConfiguration() -> ClassDiagramConfiguration {
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = grouping
            configuration.minimumAccessLevel = minAccess
            if hideMembers {
                configuration.showProperties = false
                configuration.showMethods = false
            }
            configuration.focus = FocusOptionBuilder(
                rootTypeName: focus,
                depth: focusDepth,
                direction: focusDirection,
                relationshipKinds: focusRelationship,
                includeInterconnections: !noFocusInterconnections
            ).configuration
            // A focused view is a local neighbourhood around one type; module/directory boxing splits
            // it into mismatched clusters that waste canvas. Lay it out as a single graph so the root
            // is prominent and the space is filled.
            if configuration.focus != nil {
                configuration.grouping = .none
            }
            return configuration
        }
    }
}

extension ClassDiagramConfiguration.Grouping: ExpressibleByArgument {}
#endif
