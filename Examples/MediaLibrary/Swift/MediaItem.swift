import Foundation

/// Shared base for every item in the library.
open class MediaItem: Playable {
    public let title: String
    public let duration: TimeInterval
    public let genre: Genre

    public init(title: String, duration: TimeInterval, genre: Genre) {
        self.title = title
        self.duration = duration
        self.genre = genre
    }

    open func play() {
        print("Playing \(title)…")
    }
}
