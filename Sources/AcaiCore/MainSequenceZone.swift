/// Which side of Robert Martin's main sequence (`A + I = 1`) a module falls on: the two corners he
/// names as worth a second look, plus a deliberately wide balanced band around the line itself.
///
/// A closed enum by design — the shared vocabulary the diagram renderers and the app's chart both
/// classify against, so one module lands in one zone whichever surface reports it.
public enum MainSequenceZone: String, Codable, Sendable, CaseIterable {
    /// Stable and concrete: hard to extend without breaking dependents.
    case painful
    /// Unstable and abstract: abstraction whose cost isn't earning its keep, since barely anything
    /// depends on it.
    case useless
    case balanced

    /// Modules nearer the line than this are balanced whichever side they sit on.
    private static let balancedDistance = 0.3

    public init(instability: Double, distanceFromMainSequence: Double) {
        guard distanceFromMainSequence >= Self.balancedDistance else {
            self = .balanced
            return
        }
        self = instability < 0.5 ? .painful : .useless
    }

    /// Untranslated: this reaches DOT, Mermaid and CLI output, all of which leave the app bundle.
    public var label: String {
        switch self {
        case .painful:
            "zone of pain"
        case .useless:
            "zone of uselessness"
        case .balanced:
            "balanced"
        }
    }
}

extension CodeMetrics.ModuleCoupling {
    public var mainSequenceZone: MainSequenceZone {
        MainSequenceZone(instability: instability, distanceFromMainSequence: distanceFromMainSequence)
    }
}
