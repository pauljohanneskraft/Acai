import ArgumentParser
import AcaiCore
import AcaiDiagram
import AcaiQuality

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

    @Option(name: .long, help: ArgumentHelp(
        "Colour nodes by this metric's value, using bands from --rules (or the built-in defaults)."
        + " The metric must be per-type and have a `colorBands` entry in the rules file."
    ))
    var colorBy: MetricBudget.Metric?

    @Option(name: .long, help: "Path to a code-quality rules YAML file supplying --color-by's colour bands.")
    var rules: String?

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

    /// Wires `--color-by` onto `options`: looks up its band in the loaded (or default) rules file,
    /// then colours and annotates every type the band's metric applies to. A no-op when `--color-by`
    /// wasn't given.
    func applyColorBy(to options: inout ClassDiagramOptions, artifact: CodeArtifact) throws {
        guard let metric = colorBy else { return }
        guard !metric.isModuleScoped else {
            throw ValidationError(
                "--color-by \(metric.rawValue) is a per-module metric; class-diagram colouring needs a per-type metric."
            )
        }
        let ruleSet = try rules.map { try QualityRules.load(contentsOf: $0) } ?? QualityRules.defaultQuality
        guard let band = ruleSet.colorBands.first(where: { $0.metric == metric }) else {
            throw ValidationError(
                "No colour band is defined for metric '\(metric.rawValue)'. Add a `colorBands` entry"
                + " for it to the rules file passed via --rules."
            )
        }
        let coloring = band.coloring(for: artifact.computeMetrics().types)
        options.nodeColorOverride = { coloring[$0.id]?.hex }
        options.nodeAnnotation = { type in
            coloring[type.id].map { "\(metric.rawValue): \($0.formattedValue)" }
        }
    }
}

// Lives here, not in the macOS-only `ImageCommand`, so it resolves on every platform.
extension AccessLevel: ExpressibleByArgument {}
extension MetricBudget.Metric: ExpressibleByArgument {}
