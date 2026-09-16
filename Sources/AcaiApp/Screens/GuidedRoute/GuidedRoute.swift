import Foundation

/// A short, ordered tour through a freshly indexed codebase, assembled entirely from measurements
/// already taken: where execution enters, what's most depended-upon, and where complexity
/// concentrates. See `GuidedRouteBuilder`.
struct GuidedRoute: Identifiable, Equatable {
    struct Stop: Identifiable, Equatable {
        enum Kind: String, Equatable, Hashable, CaseIterable {
            case entryPoint
            case mostDependedUpon
            case mostComplex
        }

        var id: Kind { kind }
        let kind: Kind
        /// The concrete method or type this stop points at, e.g. `"AppDelegate.run"` or `"UserStore"`.
        let subject: String
        let content: GeneratedDiagram.Content
    }

    let id = UUID()
    let projectID: UUID
    let codebaseID: UUID
    let stops: [Stop]
}
