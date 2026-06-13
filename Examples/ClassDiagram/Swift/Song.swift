import Foundation

/// A single track by an artist.
public final class Song: MediaItem {
    public let artist: String
    public let album: String?

    public init(title: String, duration: TimeInterval, genre: Genre, artist: String, album: String? = nil) {
        self.artist = artist
        self.album = album
        super.init(title: title, duration: duration, genre: genre)
    }

    public override func play() {
        print("♪ \(artist) — \(title)")
    }
}
