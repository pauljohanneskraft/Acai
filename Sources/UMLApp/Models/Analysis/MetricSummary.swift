import UMLCore

/// A codebase-wide aggregate of one numeric metric over a collection of elements (types or modules):
/// the average and maximum, plus the element achieving the maximum (the card's exemplar). Built by
/// reducing e.g. `computeMetrics().types` or `.modules` over a value extractor, so each statistic card
/// is one `MetricSummary`.
struct MetricSummary<Element> {
    let average: Double
    let maximum: Double
    /// Every element achieving `maximum` (so ties are all named on the card). Empty for an empty
    /// collection. Order follows the input order.
    let exemplars: [Element]

    init(_ elements: [Element], value: (Element) -> Double) {
        guard !elements.isEmpty else {
            average = 0
            maximum = 0
            exemplars = []
            return
        }
        let values = elements.map(value)
        average = values.reduce(0, +) / Double(elements.count)
        let maxValue = values.max() ?? 0
        maximum = maxValue
        exemplars = zip(elements, values).filter { $0.1 == maxValue }.map(\.0)
    }
}
