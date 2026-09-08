import ArgumentParser
import AcaiCore
import AcaiDiagram

/// The diagram-mode and focus options declared identically by the `diagram` and `image` commands:
/// which alternate diagram (sequence/state/package/call-graph) to render instead of a class diagram,
/// and how to focus a class diagram on one type's neighbourhood. Declared once here so a new option
/// — or a fix to one — reaches both commands by construction instead of needing to be applied twice.
struct DiagramShapeFlags: ParsableArguments {
    @Option(name: .long, help: ArgumentHelp(
        "Render a sequence diagram traced from this entry point instead of a class diagram." +
        " Format: \"TypeName.methodName\", or \"functionName\" for a top-level function."
    ))
    var sequenceFrom: String?

    @Option(name: .long, help: ArgumentHelp(
        "Resolve an interface/protocol to a concrete type when tracing a sequence diagram." +
        " Repeat for multiple: --map Protocol=Concrete --map Other=Impl."
    ))
    var map: [String] = []

    @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
    var maxDepth: Int = 5

    @Option(name: .long, help: ArgumentHelp(
        "Render a value-flow state diagram for this variable instead of a class diagram." +
        " Format: \"TypeName.variableName\", or just \"variableName\" for a global."
    ))
    var stateFrom: String?

    @Option(name: .long, help: "Maximum number of distinct states before the analysis fails.")
    var maxStates: Int = 20

    @Flag(name: .long, help: ArgumentHelp(
        "Render a package/module dependency diagram (one node per build module, with"
        + " coupling metrics) instead of a class diagram."
    ))
    var package: Bool = false

    @Flag(name: .long, help: ArgumentHelp(
        "Render a static call graph (one node per method, edges for resolvable calls)"
        + " instead of a class diagram."
    ))
    var callGraph: Bool = false

    @Option(name: .long, help: ArgumentHelp(
        "Scope the call graph to a single type or build module:"
        + " \"type:Name\" or \"module:Name\". Defaults to the whole codebase."
    ))
    var callGraphScope: String?

    @Option(name: .long, help: ArgumentHelp(
        "Focus the class diagram on a single type, showing only the subgraph around it."
        + " Pass the type name."
    ))
    var focus: String?

    @Option(name: .long, help: ArgumentHelp(
        "Maximum focus traversal depth (1 = the type plus its direct neighbours)."
        + " Omit for unlimited."
    ))
    var focusDepth: Int?

    @Option(name: .long, help: "Focus traversal direction: dependencies, dependents, both.")
    var focusDirection: FocusDirectionOption?

    @Option(name: .long, help: ArgumentHelp(
        "Restrict focus to one or more relationship kinds (e.g. inheritance)."
        + " Repeat the flag for multiple. Defaults to all kinds."
    ))
    var focusRelationship: [RelationshipKindOption] = []

    @Flag(name: .long, help: ArgumentHelp(
        "When focusing, draw only the edges actually walked, not every edge among the"
        + " selected types."
    ))
    var noFocusInterconnections: Bool = false

    /// Mode exclusivity (`--sequence-from`/`--state-from`/`--package`/`--call-graph`), `--call-graph-
    /// scope` requiring `--call-graph`, and the shared depth/state limits.
    func validate() throws {
        if sequenceFrom != nil && stateFrom != nil {
            throw ValidationError("Specify either --sequence-from or --state-from, not both.")
        }
        let modeFlags = [sequenceFrom != nil, stateFrom != nil, package, callGraph].filter { $0 }.count
        if modeFlags > 1 {
            throw ValidationError(
                "Specify only one of --sequence-from, --state-from, --package, or --call-graph."
            )
        }
        if callGraphScope != nil && !callGraph {
            throw ValidationError("--call-graph-scope requires --call-graph.")
        }
        try DiagramLimits().validate(maxDepth: maxDepth, maxStates: maxStates)
    }

    var callGraphScopeOption: CallGraphScopeOption {
        CallGraphScopeOption(raw: callGraphScope)
    }

    var focusConfiguration: FocusConfiguration? {
        FocusOptionBuilder(
            rootTypeName: focus, depth: focusDepth, direction: focusDirection,
            relationshipKinds: focusRelationship, includeInterconnections: !noFocusInterconnections
        ).configuration
    }
}
