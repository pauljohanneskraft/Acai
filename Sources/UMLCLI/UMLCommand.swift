import ArgumentParser
import Foundation
import Yams

@main
struct UMLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uml",
        abstract: "UML diagram generator from source code",
        subcommands: subcommandList
    )

    private static var subcommandList: [any ParsableCommand.Type] {
        var commands: [any ParsableCommand.Type] = [Analyze.self, Store.self, List.self, Diagram.self, Metrics.self]
        // `image` renders via SwiftUI's ImageRenderer (UMLRender), available on macOS only.
        #if canImport(SwiftUI)
        commands.append(Image.self)
        #endif
        return commands
    }
}
