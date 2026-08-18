import AcaiCore

/// Chart-ready view over `CodeMetrics.ModuleCoupling`: one point per module on Robert
/// Martin's Abstractness-vs-Instability "main sequence" chart, plus which zone it falls in relative
/// to the main sequence line (`A + I = 1`) — the modules farthest from the line, in either
/// direction, are the ones worth a second look.
///
/// A plain value built once from already-computed metrics (never recomputed in a view's `body`) —
/// `CodeMetrics.computeMetrics()` is a real, non-trivial walk of the artifact (LCOM, feature envy,
/// fan-in/out, …), so callers compute it once (e.g. in a view's `init` or a `.task`) and hand the
/// resulting `[CodeMetrics.ModuleCoupling]` in here.
struct ModuleCouplingChartData {
    /// One module's plotted point. `Zone` is the required non-color signal (alongside
    /// `Charts`' categorical `.symbol(by:)` shape and the ranked legend list): every point's zone is
    /// also stated in text, never conveyed by color alone.
    struct Point: Identifiable, Equatable {
        let id: String
        let name: String
        let instability: Double
        let abstractness: Double
        let distance: Double
        let publicMemberCount: Int
        let zone: Zone
    }

    /// The two "worth a second look" corners Martin names, plus the (deliberately wide) balanced
    /// band around the line itself. A closed, real-vocabulary enum — not a namespace — consumed
    /// exhaustively by the chart's shape/color scale and the legend list.
    enum Zone: String, CaseIterable, Identifiable {
        /// Stable and concrete (low instability, low abstractness): hard to extend without
        /// breaking dependents.
        case painful = "Zone of Pain"
        /// Unstable and abstract (high instability, high abstractness): abstraction whose cost
        /// isn't earning its keep, since barely anything depends on it.
        case useless = "Zone of Uselessness"
        case balanced = "Balanced"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .painful:
                "triangle.fill"
            case .useless:
                "square.fill"
            case .balanced:
                "circle.fill"
            }
        }
    }

    let points: [Point]

    /// The line itself is fixed geometry (`A + I = 1`, from `(0, 1)` to `(1, 0)`) rather than data —
    /// callers draw it directly rather than reading it off this type.
    init(modules: [CodeMetrics.ModuleCoupling]) {
        points = modules.map { module in
            Point(
                id: module.name,
                name: module.name,
                instability: module.instability,
                abstractness: module.abstractness,
                distance: module.distanceFromMainSequence,
                publicMemberCount: module.publicMemberCount,
                zone: module.mainSequenceZone
            )
        }
    }

    var rankedByDistance: [Point] {
        points.sorted { $0.distance > $1.distance }
    }
}

extension CodeMetrics.ModuleCoupling {
    /// Which side of the main sequence this module falls on, per `ModuleCouplingChartData.Zone`'s
    /// documentation — a computed property on the value the classification actually describes,
    /// rather than a free-standing helper function.
    fileprivate var mainSequenceZone: ModuleCouplingChartData.Zone {
        guard distanceFromMainSequence >= 0.3 else { return .balanced }
        return instability < 0.5 ? .painful : .useless
    }
}
