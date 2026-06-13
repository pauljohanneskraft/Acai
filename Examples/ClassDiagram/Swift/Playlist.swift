import Foundation

/// An ordered collection of media items the user has curated.
public struct Playlist {
    public let name: String
    public private(set) var items: [MediaItem]

    public init(name: String, items: [MediaItem] = []) {
        self.name = name
        self.items = items
    }

    public var totalDuration: TimeInterval {
        items.reduce(0) { $0 + $1.duration }
    }

    public mutating func add(_ item: MediaItem) {
        items.append(item)
    }
}
