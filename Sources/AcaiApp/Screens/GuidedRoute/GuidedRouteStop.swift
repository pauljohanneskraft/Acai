struct GuidedRouteStop: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Hashable, CaseIterable, Sendable {
        case entryPoint
        case mostDependedUpon
        case mostComplex
    }

    var id: Kind { kind }
    let kind: Kind
    /// The method or type this stop points at, e.g. `"AppDelegate.run"` or `"UserStore"`.
    let subject: String
    let content: GeneratedDiagram.Content
}
