/// The headline shape of one metric across a set of elements: its average, its maximum, and every
/// element achieving that maximum so ties are all named.
public struct MetricSummary<Element> {
    public let average: Double
    public let maximum: Double
    /// Every element achieving `maximum`, so ties are all named on the card.
    public let exemplars: [Element]

    public init(_ elements: [Element], value: (Element) -> Double) {
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
