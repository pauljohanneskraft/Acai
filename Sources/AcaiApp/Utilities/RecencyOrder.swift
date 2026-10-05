import Foundation

/// Use order over the keys of a bounded cache, least recently used first.
///
/// It holds keys only: the caches it bounds keep their own storage — some `@Published`, some filled
/// lazily during a view update — so it answers "which keys to drop" rather than owning the values.
struct RecencyOrder<Key: Hashable> {
    /// How many keys a cache may hold before `overflow(retaining:)` starts dropping its oldest.
    let capacity: Int

    private var keys: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Least recently used first.
    var ordered: [Key] { keys }

    /// Marks `key` as the most recently used, adding it when it is new.
    mutating func use(_ key: Key) {
        keys.removeAll { $0 == key }
        keys.append(key)
    }

    /// Removes and returns the keys past `capacity`, least recently used first. A `retaining` key is
    /// kept however old it is, so a cache stays over its bound while that many entries are in use
    /// rather than dropping one the caller is still reading.
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

    /// Removes and returns every key except `retaining`.
    mutating func purge(retaining: Set<Key>) -> [Key] {
        let dropped = keys.filter { !retaining.contains($0) }
        keys.removeAll { !retaining.contains($0) }
        return dropped
    }
}
