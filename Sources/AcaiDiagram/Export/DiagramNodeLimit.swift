/// A ceiling on the number of nodes a class or package diagram may contain before generation fails,
/// shared by every front end (the CLI `diagram`/`image` commands, the MCP `acai_diagram`/`acai_image`
/// tools, the app) so the same threshold and message reach all of them. `nil` means unlimited, which
/// existing callers and already-persisted app configurations keep getting unless they opt in.
public struct DiagramNodeLimit: Sendable {
    /// Applied by every front end unless the caller overrides it.
    public static let defaultMaximum = 2000

    public var maximum: Int?

    public init(maximum: Int?) {
        self.maximum = maximum
    }

    public func validate(nodeCount: Int) throws {
        guard let maximum, nodeCount > maximum else { return }
        throw DiagramRequestError(
            "This diagram has \(nodeCount) nodes, exceeding the limit of \(maximum). "
                + "Narrow the scope with a focus type, or raise the node limit."
        )
    }
}
