import Foundation

/// One episode of a podcast.
public final class Podcast: MediaItem {
    public let host: String
    public let episodeNumber: Int

    public init(title: String, duration: TimeInterval, host: String, episodeNumber: Int) {
        self.host = host
        self.episodeNumber = episodeNumber
        super.init(title: title, duration: duration, genre: .spokenWord)
    }

    public override func play() {
        print("🎙 Episode \(episodeNumber): \(title)")
    }
}
