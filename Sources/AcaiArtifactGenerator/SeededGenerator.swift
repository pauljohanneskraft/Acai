/// A deterministic `RandomNumberGenerator` (SplitMix64), so a property-based test that fails can be
/// replayed exactly from the seed it reports. Swift's `SystemRandomNumberGenerator` cannot be seeded.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed &+ 0x9e37_79b9_7f4a_7c15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var result = state
        result = (result ^ (result >> 30)) &* 0xbf58_476d_1ce4_e5b9
        result = (result ^ (result >> 27)) &* 0x94d0_49bb_1331_11eb
        return result ^ (result >> 31)
    }
}

extension SeededGenerator {
    /// A value in `0..<count`, or `nil` for an empty range.
    mutating func index(below count: Int) -> Int? {
        guard count > 0 else { return nil }
        return Int(next() % UInt64(count))
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func bool(probability: Double = 0.5) -> Bool {
        Double(next() % 1000) / 1000 < probability
    }

    mutating func pick<Element>(_ elements: [Element]) -> Element? {
        index(below: elements.count).map { elements[$0] }
    }

    /// `count` picks from `elements`, deduplicated by `keyPath` so a caller building a set-like list
    /// (modifiers, annotations) never gets the same entry twice.
    mutating func picks<Element, Key: Hashable>(
        _ count: Int, from elements: [Element], uniqueBy keyPath: KeyPath<Element, Key>
    ) -> [Element] {
        var seen: Set<Key> = []
        var result: [Element] = []
        for _ in 0..<count {
            guard let element = pick(elements), seen.insert(element[keyPath: keyPath]).inserted else { continue }
            result.append(element)
        }
        return result
    }
}
