import Foundation

/// Least-recently-used order over a bounded cache's keys; the cache keeps its own storage.
struct RecencyOrder<Key: Hashable> {
    let capacity: Int

    private var keys: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Least recently used first.
    var ordered: [Key] { keys }

    mutating func use(_ key: Key) {
        keys.removeAll { $0 == key }
        keys.append(key)
    }

    /// A `retaining` key is never dropped, even if that leaves the order over `capacity`.
    mutating func overflow(retaining: Set<Key>) -> [Key] {
        var dropped: [Key] = []
        var index = 0
        while keys.count > capacity, index < keys.count {
            if retaining.contains(keys[index]) {
                index += 1
            } else {
                dropped.append(keys.remove(at: index))
            }
        }
        return dropped
    }

    mutating func purge(retaining: Set<Key>) -> [Key] {
        let dropped = keys.filter { !retaining.contains($0) }
        keys.removeAll { !retaining.contains($0) }
        return dropped
    }
}
