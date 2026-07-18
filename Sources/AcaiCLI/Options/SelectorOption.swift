import ArgumentParser
import AcaiQuality
import AcaiCore

extension TypeKind: ExpressibleByArgument {}
extension MemberKind: ExpressibleByArgument {}
// `AccessLevel: ExpressibleByArgument` is already declared in ClassDiagramFlags.swift.

/// The shared type-selector flags (`--module`, `--type`, `--kind`, …) that narrow which types a
/// query-style command reports on. `@OptionGroup`-ed into `inspect` and `smells` so the flag set and
/// its mapping onto the engine's `Selector` live in one place. Every facet is optional and
/// AND-combined by `Selector.matches`; naming no language, it resolves `stereotype`/`annotation`
/// against the artifact's injected `LanguageConfiguration`.
struct SelectorOption: ParsableArguments {
    @Option(name: .long, help: "Only types whose module/target matches this name or glob (*, ?).")
    var module: String?

    @Option(name: .long, help: "Only types whose id / qualified name matches this glob (*, ?).")
    var type: String?

    @Option(name: .long, help: "Only types of this declaration kind (e.g. class, protocol, struct).")
    var kind: TypeKind?

    @Option(name: .long, help: "Only types with at least this visibility (e.g. public).")
    var minAccess: AccessLevel?

    @Option(name: .long, help: "Only types carrying this UML stereotype (e.g. entity, repository).")
    var stereotype: String?

    @Option(name: .long, help: "Only types carrying this annotation marker (e.g. Entity).")
    var annotation: String?

    @Option(name: .long, help: "Only types with at least this many members (find god types).")
    var minMembers: Int?

    @Option(name: .long, help: "Only types nested at least this deep.")
    var minNesting: Int?

    /// The engine `Selector` these flags describe. A selector with no flags set matches every type.
    var selector: Selector {
        Selector(
            module: module,
            typeGlob: type,
            stereotype: stereotype,
            annotation: annotation,
            minimumAccess: minAccess,
            kind: kind,
            minMembers: minMembers,
            minNesting: minNesting
        )
    }
}
