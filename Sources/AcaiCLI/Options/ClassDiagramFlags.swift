import ArgumentParser
import AcaiCore
import AcaiDiagram

struct ClassDiagramFlags: ParsableArguments {
    @Option(name: .long, help: "Graph layout direction: TB, LR, BT, RL.")
    var direction: DirectionOption?

    @Option(name: .long, help: "Grouping strategy: file, namespace, none.")
    var groupBy: GroupByOption?

    @Flag(name: .long, help: "Show type members in the diagram.")
    var showMembers: Bool = false

    @Flag(name: .long, help: "Hide type members from the diagram.")
    var noShowMembers: Bool = false

    @Option(name: .long, help: ArgumentHelp(
        "Hide members below this access level (class diagram only): open, public,"
        + " packagePrivate, protected, internal, filePrivate, private."
    ))
    var minAccess: AccessLevel?

    @Flag(name: .long, help: "Include external (referenced-but-undefined) types as placeholder nodes.")
    var showExternalTypes: Bool = false

    @Flag(name: .long, help: "Do not infer composition/aggregation edges from property types.")
    var noInferComposition: Bool = false

    @Flag(name: .long, help: "Do not infer dependency edges from method parameter/return types.")
    var noInferDependency: Bool = false

    /// Applies the set flags onto `options`; unset flags leave the existing value (e.g. from
    /// `--config` applied earlier).
    func apply(to options: inout ClassDiagramOptions) {
        if let direction { options.layoutDirection = direction.layoutDirection }
        if let groupBy { options.groupBy = groupBy.groupingStrategy }
        if showMembers { options.showMembers = true }
        if noShowMembers { options.showMembers = false }
        if let minAccess { options.minimumAccessLevel = minAccess }
        if showExternalTypes { options.showExternalTypes = true }
        if noInferComposition { options.inferCompositionFromProperties = false }
        if noInferDependency { options.inferDependencyFromMethods = false }
    }
}

// Lives here, not in the macOS-only `ImageCommand`, so it resolves on every platform.
extension AccessLevel: ExpressibleByArgument {}
