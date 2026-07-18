import ArgumentParser
import Foundation
import Yams

@main
struct AcaiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "acai",
        abstract: "UML diagram generator from source code",
        subcommands: subcommandList
    )

    private static var subcommandList: [any ParsableCommand.Type] {
        var commands: [any ParsableCommand.Type] = [
            Analyze.self, Store.self, List.self, Diagram.self, Metrics.self, Diff.self,
            Quality.self, Rules.self, Inspect.self, CallGraph.self, Impact.self
        ]
        // `image` renders via SwiftUI's ImageRenderer (AcaiRender), which is linked into the CLI on
        // macOS only (see Package.swift). Gate on os(macOS) to mirror that dependency condition.
        #if os(macOS)
        commands.append(Image.self)
        #endif
        return commands
    }
}
