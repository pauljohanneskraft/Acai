// Churn comes from `AcaiGit` (libgit2), which is linked into the CLI on macOS only — the same
// gating `image`/`AcaiRender` uses.
#if os(macOS)
import ArgumentParser
import Foundation
import AcaiCore
import AcaiGit
import AcaiLibrary
import AcaiQuality

extension AcaiCommand {
    struct Hotspots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hotspots",
            abstract: "Rank files by churn × complexity — where a refactoring budget buys the most"
        )

        @Option(name: .long, help: "Path to a source directory inside a git checkout.")
        var source: String

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages (\(LanguageOption.allValuesList))."
            + " Repeat the flag for multiple: --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        @OptionGroup var generatedScope: GeneratedScopeOption

        @Option(name: .long, help: "How many commits of history to walk for churn.")
        var commits: Int = 50

        @Option(name: .long, help: "Limit the report to the top N hotspots.")
        var top: Int?

        @Option(name: .long, help: "Report format: human (default) or json.")
        var format: ReportFormatOption = .human

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            guard commits > 0 else {
                throw ValidationError("--commits must be at least 1.")
            }
            if let top, top < 1 {
                throw ValidationError("--top must be at least 1.")
            }
        }

        mutating func run() async throws {
            let url = URL(fileURLWithPath: source).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ValidationError("Source directory does not exist: \(source)")
            }
            let churn = try churnByFile(at: url)
            let artifact = try await generatedScope.applied(
                to: ArtifactSource.resolve(from: nil, source: source, language: language))
            let report = HotspotsReport(
                hotspots: AcaiQuality.Hotspots(artifact: artifact, churnByFile: churn),
                commitWindow: commits, top: top)
            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(report).text
            case .human:
                rendered = report.text
            }
            try rendered.writeOutput(to: output, label: "hotspots")
        }

        /// Churn is the whole point of the report, so "no history here" is an error naming what is
        /// missing rather than a ranked list that is silently empty.
        private func churnByFile(at url: URL) throws -> [String: Int] {
            do {
                guard let churn = try DirectoryChurn(directory: url).byFile(limit: commits) else {
                    throw ValidationError(
                        "\(url.path) is not inside a git checkout. Hotspots rank files by how often they "
                        + "change against how complex they are, so they need a repository with commit history."
                    )
                }
                return churn
            } catch is HistoryNotFetched {
                throw ValidationError(
                    "\(url.path) is a shallow clone, so only the commits it happens to hold could be counted. "
                    + "Run `git fetch --unshallow` there first."
                )
            }
        }
    }
}

/// The ranked list, in both output formats. `--top` is applied once, here, so the human table and
/// the JSON report can never disagree about which rows are in scope.
private struct HotspotsReport: Encodable {
    let churnThreshold: Double
    let complexityThreshold: Double
    let commitWindow: Int
    let filesScored: Int
    /// Every file above both medians, even when `--top` shows fewer.
    let hotspotCount: Int
    let hotspots: [Hotspots.File]

    init(hotspots: Hotspots, commitWindow: Int, top: Int?) {
        churnThreshold = hotspots.churnThreshold
        complexityThreshold = hotspots.complexityThreshold
        self.commitWindow = commitWindow
        filesScored = hotspots.files.count
        let ranked = hotspots.ranked
        hotspotCount = ranked.count
        self.hotspots = top.map { Array(ranked.prefix($0)) } ?? ranked
    }

    var text: String {
        let header = """
            Hotspots — churn × complexity over the last \(commitWindow) commits
            \(filesScored) files scored, \(hotspotCount) above both medians \
            (churn \(formatted(churnThreshold)), complexity \(formatted(complexityThreshold)))
            """
        guard !hotspots.isEmpty else {
            return header + "\n\nNo file is above both medians — no hotspot stands out in this window. "
                + "Widen it with --commits to look further back.\n"
        }
        let rows = hotspots.map {
            "\(String($0.score).paddedLeading(to: 7))\(String($0.churn).paddedLeading(to: 8))"
            + "\(String($0.complexity).paddedLeading(to: 13))  \($0.path)"
        }
        return ([header, "", "  SCORE   CHURN   COMPLEXITY  FILE"] + rows).joined(separator: "\n") + "\n"
    }

    private func formatted(_ threshold: Double) -> String {
        threshold.rounded() == threshold ? String(Int(threshold)) : String(format: "%.1f", threshold)
    }
}
#endif
