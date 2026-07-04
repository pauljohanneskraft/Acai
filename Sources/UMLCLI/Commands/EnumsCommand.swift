import ArgumentParser
import UMLCore
import UMLLibrary

extension UMLCommand {
    /// Enumerates every enum-like type with its cases, raw values and associated-value shapes, each
    /// carrying `file:line`.
    struct Enums: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List enum cases with raw values and associated values as JSON/human"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let entries = EnumInventory(artifact: try artifactSource.resolve()).entries
            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(entries).text
            case .human:
                rendered = humanReport(entries)
            }
            try rendered.writeOutput(to: output, label: "enum inventory")
        }

        private func humanReport(_ entries: [EnumInventory.Entry]) -> String {
            guard !entries.isEmpty else { return "No enums found.\n" }
            var lines: [String] = []
            for entry in entries {
                lines.append("\(entry.type)\(entry.location.suffix)")
                for enumCase in entry.cases {
                    var text = "  - \(enumCase.name)"
                    if !enumCase.associatedValues.isEmpty {
                        text += "(\(enumCase.associatedValues.joined(separator: ", ")))"
                    }
                    if let rawValue = enumCase.rawValue {
                        text += " = \(rawValue)"
                    }
                    lines.append(text)
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
