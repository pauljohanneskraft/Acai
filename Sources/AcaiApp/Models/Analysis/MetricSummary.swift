import AcaiCore

struct MetricSummary<Element> {
    let average: Double
    let maximum: Double
    /// Every element achieving `maximum`, so ties are all named on the card.
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
