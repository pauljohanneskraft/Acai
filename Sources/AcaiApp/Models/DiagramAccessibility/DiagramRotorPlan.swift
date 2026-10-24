import CoreGraphics
import AcaiDiff

/// VoiceOver's reading order over a canvas — rows top to bottom, leading to trailing — and its rotors' entries.
struct DiagramRotorPlan {
    struct Element: Identifiable, Equatable {
        let id: String
        /// Parser content, never translated.
        let label: String
        let delta: DeltaStatus?
        let frame: CGRect
    }

    let elements: [Element]
    let connections: [Element]
    private let priorities: [String: Double]

    init(elements: [Element], connections: [Element] = []) {
        self.elements = elements.inReadingOrder
        self.connections = connections.inReadingOrder
        self.priorities = Dictionary(
            (self.elements + self.connections).enumerated().map { ($0.element.id, -Double($0.offset + 1)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var changed: [Element] {
        (elements + connections).filter { $0.delta.isChange }
    }

    /// Below the default 0, so any other canvas element stays ahead of it in order and in hit testing.
    func sortPriority(of id: String) -> Double {
        priorities[id] ?? 0
    }
}

extension DiagramRotorPlan.Element {
    /// The 44pt square a connection's accessibility element occupies at `midpoint`.
    init(connection id: String, label: String, delta: DeltaStatus?, midpoint: CGPoint) {
        self.init(
            id: id, label: label, delta: delta,
            frame: CGRect(x: midpoint.x - 22, y: midpoint.y - 22, width: 44, height: 44)
        )
    }

    init(connection id: String, label: String, delta: DeltaStatus?, from source: CGRect, to target: CGRect) {
        self.init(
            connection: id, label: label, delta: delta,
            midpoint: CGPoint(x: (source.midX + target.midX) / 2, y: (source.midY + target.midY) / 2)
        )
    }
}

extension [DiagramRotorPlan.Element] {
    /// An element starting above the centre line of its row's topmost element reads in that row.
    fileprivate var inReadingOrder: [DiagramRotorPlan.Element] {
        let topDown = sorted { ($0.frame.minY, $0.frame.minX, $0.id) < ($1.frame.minY, $1.frame.minX, $1.id) }
        var rows: [[DiagramRotorPlan.Element]] = []
        for element in topDown {
            if let first = rows.last?.first, element.frame.minY < first.frame.midY {
                rows[rows.count - 1].append(element)
            } else {
                rows.append([element])
            }
        }
        return rows.flatMap { row in
            row.sorted { ($0.frame.minX, $0.id) < ($1.frame.minX, $1.id) }
        }
    }
}

extension DeltaStatus? {
    fileprivate var isChange: Bool {
        switch self {
        case .added, .removed, .changed:
            true
        case .unchanged, nil:
            false
        }
    }
}
