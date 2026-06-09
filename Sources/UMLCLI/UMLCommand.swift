import ArgumentParser
import Foundation
import Yams

@main
struct UMLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uml",
        abstract: "UML diagram generator from source code",
        subcommands: subcommandList
    )

    private static var subcommandList: [any ParsableCommand.Type] {
        var commands: [any ParsableCommand.Type] = [Analyze.self, Store.self, List.self, Diagram.self, Metrics.self]
        // `image` renders via SwiftUI's ImageRenderer (UMLRender), which is linked into the CLI on
        // macOS only (see Package.swift). Gate on os(macOS) to mirror that dependency condition.
        #if os(macOS)
        commands.append(Image.self)
        #endif
        return commands
    }
}
