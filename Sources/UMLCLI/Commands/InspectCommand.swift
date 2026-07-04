import ArgumentParser
import UMLConformance
import UMLCore
import UMLLibrary

extension UMLCommand {
    /// Enumerates types and their members, filtered by a type `Selector` + member facets, each row
    /// carrying `file:line`. The highest-leverage query for an agent: "which public classes in module
    /// X have a method with 4+ parameters?" answered as JSON jump targets.
    struct Inspect: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enumerate types and members as JSON/human, filtered by a selector",
            aliases: ["query"]
        )

        @OptionGroup var artifactSource: ArtifactSource
        @OptionGroup var selector: SelectorOption

        @Option(name: .long, help: "Only members of this kind (e.g. method, property, initializer).")
        var memberKind: MemberKind?

        @Option(name: .long, help: "Only members with at least this many parameters.")
        var minParameters: Int?

        @Flag(name: .long, help: "Only publicly-settable stored properties (mutable public state).")
        var publicVars = false

        @Flag(name: .long, help: "Only members that override an inherited member.")
        var overrides = false

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let rows = TypeQuery(
                artifact: artifact,
                selector: selector.selector,
                members: MemberFilter(
                    kind: memberKind,
                    minParameters: minParameters,
                    isPublicVar: publicVars ? true : nil,
                    isOverride: overrides ? true : nil),
                annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
            ).rows

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(rows).text
            case .human:
                rendered = humanReport(rows)
            }
            try rendered.writeOutput(to: output, label: "inspection")
        }

        private func humanReport(_ rows: [TypeQuery.TypeRow]) -> String {
            guard !rows.isEmpty else { return "No types matched.\n" }
            var lines: [String] = []
            for row in rows {
                lines.append("\(row.qualifiedName) [\(row.kind.rawValue), \(row.module)]\(row.location.suffix)")
                for member in row.members {
                    let params = member.parameterCount > 0 ? "(\(member.parameterCount))" : ""
                    lines.append(
                        "  - \(member.name)\(params): \(member.kind.rawValue) "
                        + "(\(member.access.rawValue))\(member.location.suffix)")
                }
            }
            lines.append("")
            lines.append("\(rows.count) type(s) matched.")
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
