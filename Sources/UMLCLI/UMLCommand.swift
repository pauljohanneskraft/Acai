import ArgumentParser
import Foundation
import UMLLibrary
import Yams

@main
struct UMLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uml",
        abstract: "UML diagram generator from source code",
        subcommands: [Analyze.self, Store.self, List.self, Diagram.self]
    )
}
