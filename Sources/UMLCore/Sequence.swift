import Foundation

extension Sequence {
    public func removingDuplicates<H: Hashable>(by property: (Element) -> H) -> [Element] {
        var existing = Set<H>()
        return filter { existing.insert(property($0)).inserted }
    }
}