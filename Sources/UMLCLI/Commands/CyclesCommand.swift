import ArgumentParser
import Foundation
import UMLConformance
import UMLLibrary

extension UMLCommand {
    /// Detects dependency cycles (strongly-connected components) at module and/or type scope.
    /// Module cycles are provenance-aware, so cross-module extensions don't fabricate false cycles.
    struct Cycles: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Detect dependency cycles at module and/or type scope"
        )

        enum ScopeOption: String, ExpressibleByArgument, CaseIterable {
            case modules
            case types
            case all
        }

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Cycle scope: modules, types, or all (default).")
        var scope: ScopeOption = .all

        @Option(name: .long, help: "Report format: human or json.")
        var format: ReportFormatOption = .human

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        @Flag(name: .long, help: "Exit 0 even when cycles are found (don't fail CI).")
        var noFail = false

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let finder = CycleFinder(
                artifact: artifact,
                languageResolver: artifact.standardLanguageResolver)

            let scopes: [CycleFinder.Scope] = scope == .all ? [.modules, .types]
                : [scope == .modules ? .modules : .types]
            let cycles = scopes.flatMap { finder.cycles(scope: $0) }

            switch format {
            case .human:
                try humanReport(cycles).writeOutput(to: output, label: "cycles")
            case .json:
                try jsonReport(cycles).writeOutput(to: output, label: "cycles")
            }

            if !cycles.isEmpty && !noFail { throw ExitCode.failure }
        }

        private func humanReport(_ cycles: [CycleFinder.Cycle]) -> String {
            guard !cycles.isEmpty else { return "No dependency cycles found.\n" }
            let lines = cycles.map { "\($0.scope.rawValue): \($0.description)" }
            return (["Found \(cycles.count) dependency cycle(s):"] + lines).joined(separator: "\n") + "\n"
        }

        private func jsonReport(_ cycles: [CycleFinder.Cycle]) -> String {
            let payload = cycles.map { CyclePayload(scope: $0.scope.rawValue, members: $0.members) }
            guard let report = try? JSONReport(payload) else { return "[]\n" }
            return report.text + "\n"
        }

        private struct CyclePayload: Codable {
            var scope: String
            var members: [String]
        }
    }
}
