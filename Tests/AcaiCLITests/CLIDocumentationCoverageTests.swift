import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

/// `AcaiCLI.md` calls itself the complete flag-by-flag reference and says every table comes from the
/// binary's own `--help`, but nothing held it to that: an option reached the page only if whoever
/// added it remembered, and `--language` went undocumented on `diff` for as long as `diff` has
/// accepted it. These compare each subcommand's generated help with the section documenting it, in
/// both directions.
@Suite("CLI documentation coverage", .timeLimit(.minutes(1)))
struct CLIDocumentationCoverageTests {

    private let page = CLIReferencePage()
    private let subcommands = AcaiCommand.configuration.subcommands
        .filter { $0.configuration.shouldDisplay }
        .map(SubcommandHelp.init)

    @Test func everyDeclaredFlagAppearsInItsCommandSection() throws {
        for subcommand in subcommands {
            let name = try #require(subcommand.commandName)
            let section = try #require(
                page.section(documenting: name),
                Comment(rawValue: "AcaiCLI.md has no `\(name)` section."))
            let undocumented = subcommand.flags.subtracting(section.flagsNamedInBackticks).sorted()
            #expect(
                undocumented.isEmpty,
                Comment(
                    rawValue: "`acai \(name) --help` declares \(undocumented), which AcaiCLI.md's "
                        + "`\(name)` section never names. Regenerate its flag table from "
                        + "`acai \(name) --help`."))
        }
    }

    @Test func noDocumentedFlagIsRejectedByTheParser() throws {
        for subcommand in subcommands {
            let name = try #require(subcommand.commandName)
            let section = try #require(page.section(documenting: name))
            let stale = section.flagsNamedInTableRows.subtracting(subcommand.flags).sorted()
            #expect(
                stale.isEmpty,
                Comment(
                    rawValue: "AcaiCLI.md's `\(name)` table names \(stale), which `acai \(name)` "
                        + "does not accept."))
        }
    }

    @Test func everySubcommandTheBuildExposesIsLinkedFromTheContents() throws {
        let linked = page.commandsLinkedFromContents
        for subcommand in subcommands {
            let name = try #require(subcommand.commandName)
            #expect(
                linked.contains(name),
                Comment(rawValue: "`\(name)` is missing from AcaiCLI.md's Contents list."))
        }
    }
}

/// One visible subcommand's `--help` screen, read for the command's own name and the flags it
/// declares. Generated through `ArgumentParser` rather than by shelling out, so it is the text the
/// binary prints without a built binary being needed to print it.
private struct SubcommandHelp {

    private let screen: String
    private let usagePrefix = "USAGE: acai "

    init(_ subcommand: any ParsableCommand.Type) {
        screen = AcaiCommand.helpMessage(for: subcommand, columns: 80)
    }

    var commandName: String? {
        screen.split(separator: "\n")
            .first { $0.hasPrefix(usagePrefix) }
            .flatMap { $0.dropFirst(usagePrefix.count).split(separator: " ").first }
            .map(String.init)
    }

    /// `--help` belongs to every command, so the page never lists it: `-h, --help` does not begin a
    /// line with its long name, which is what leaves it out here.
    var flags: Set<String> {
        guard let options = screen.components(separatedBy: "\nOPTIONS:\n").last else { return [] }
        return Set(
            options.split(separator: "\n")
                .filter { $0.hasPrefix("  --") }
                .compactMap { $0.dropFirst(2).split(separator: " ").first }
                .map(String.init))
    }
}

/// The reference page as a value, split into the `###` sections that document one command each.
/// Located by `#filePath` rather than `Bundle.module`, so it is found identically on macOS and
/// Linux — the approach `ParserGoldenCorpus` takes to its fixtures.
private struct CLIReferencePage {

    private let sections: [String: String]
    private let contents: String

    init(testFile: StaticString = #filePath) {
        let file = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AcaiCLI/AcaiCLI.docc/AcaiCLI.md")
        let markdown = (try? String(contentsOf: file, encoding: .utf8)) ?? ""

        var sections: [String: String] = [:]
        var command: String?
        var body: [Substring] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let heading = line.hasPrefix("### `") && line.hasSuffix("`")
            guard heading || line.hasPrefix("## ") else {
                body.append(line)
                continue
            }
            if let command { sections[command] = body.joined(separator: "\n") }
            command = heading ? String(line.dropFirst(5).dropLast()) : nil
            body = []
        }
        if let command { sections[command] = body.joined(separator: "\n") }

        self.sections = sections
        contents = (markdown.components(separatedBy: "\n## Contents\n").last ?? "")
            .components(separatedBy: "\n## ").first ?? ""
    }

    func section(documenting command: String) -> String? { sections[command] }

    var commandsLinkedFromContents: Set<String> {
        Set(
            contents.components(separatedBy: "[`").dropFirst().compactMap { link in
                let name = link.prefix { $0 != "`" }
                return link.dropFirst(name.count).hasPrefix("`](#") ? String(name) : nil
            })
    }
}

private extension String {

    /// Every flag the text names in backticks, wherever it names it — a table row, an italic
    /// shared-group row, or the prose around them.
    var flagsNamedInBackticks: Set<String> {
        Set(
            components(separatedBy: "`").enumerated()
                .filter { !$0.offset.isMultiple(of: 2) }
                .compactMap { $0.element.split(separator: " ").first }
                .filter { $0.hasPrefix("--") }
                .map(String.init))
    }

    /// Only the flags a table row names in its Flag column. A Notes cell cross-references other
    /// commands' flags (`image`'s `--grouping` points at `diagram`'s `--group-by`), and the prose
    /// documents a deprecated spelling that `--help` hides on purpose. A row whose Flag column is an
    /// italic shared-group name lists its flags in the Notes cell instead, so that cell counts there.
    var flagsNamedInTableRows: Set<String> {
        split(separator: "\n")
            .filter { $0.hasPrefix("| ") }
            .map { row in
                let cells = row.split(separator: "|", omittingEmptySubsequences: false)
                guard cells.count > 2 else { return String(row) }
                let flagColumn = cells[1].trimmingCharacters(in: .whitespaces)
                return flagColumn.hasPrefix("*") ? flagColumn + cells[2] : flagColumn
            }
            .joined(separator: "\n")
            .flagsNamedInBackticks
    }
}
