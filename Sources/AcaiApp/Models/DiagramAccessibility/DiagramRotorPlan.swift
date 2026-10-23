import CoreGraphics
import AcaiDiff

/// The order VoiceOver walks a canvas, and the elements each of its rotors offers.
///
/// Canvas elements are absolutely positioned, so the order SwiftUI infers for them is the order the
/// model happens to draw them in — nothing a reader can predict. This derives reading order from the
/// frames instead: rows top to bottom, each row leading to trailing.
struct DiagramRotorPlan {
    struct Element: Identifiable, Equatable {
        let id: String
        /// Content, not chrome: the element's name as the parser produced it.
        let label: String
        let delta: DeltaStatus?
        let center: CGPoint
    }

    let elements: [Element]
    private let priorities: [String: Double]

    /// Elements whose centres lie within `rowTolerance` points of the row's first read as one row.
    init(elements: [Element], rowTolerance: CGFloat = 24) {
        let topDown = elements.sorted {
            ($0.center.y, $0.center.x, $0.id) < ($1.center.y, $1.center.x, $1.id)
        }
        var rows: [[Element]] = []
        for element in topDown {
            if let first = rows.last?.first, element.center.y - first.center.y <= rowTolerance {
                rows[rows.count - 1].append(element)
            } else {
                rows.append([element])
            }
        }
        let ordered = rows.flatMap { row in
            row.sorted { ($0.center.x, $0.id) < ($1.center.x, $1.id) }
        }
        self.elements = ordered
        self.priorities = Dictionary(
            ordered.enumerated().map { ($0.element.id, Double(ordered.count - $0.offset)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The elements a comparison marks as changed, in the same reading order.
    var changed: [Element] {
        elements.filter(\.delta.isChange)
    }

    /// Higher reads first, so sweeping the canvas follows the same reading order as the rotors. Every
    /// element scores above the default 0, which keeps the nodes ahead of the edges between them.
    func sortPriority(of id: String) -> Double {
        priorities[id] ?? 0
    }
}

extension DeltaStatus? {
    /// `nil` and `.unchanged` alike mean no comparison is pointing at this element.
    fileprivate var isChange: Bool {
        switch self {
        case .added, .removed, .changed: true
        case .unchanged, nil: false
        }
    }
}
