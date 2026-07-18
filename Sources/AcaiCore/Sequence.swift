import Foundation

extension Sequence {
    public func removingDuplicates<H: Hashable>(by property: (Element) -> H) -> [Element] {
        var existing = Set<H>()
        return filter { existing.insert(property($0)).inserted }
    }
}

extension Sequence where Element: Hashable {
    /// The elements with later duplicates removed, preserving first-seen order.
    public func uniqued() -> [Element] {
        removingDuplicates(by: { $0 })
    }
}
