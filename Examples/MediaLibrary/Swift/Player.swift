import Foundation

/// Drives playback over a library. Depends on `Library` and the `Playable` protocol.
public final class Player {
    private let library: Library
    public private(set) var nowPlaying: Playable?

    public init(library: Library) {
        self.library = library
    }

    public func play(_ item: Playable) {
        nowPlaying = item
        item.play()
    }

    public func playFirstItem(inPlaylistNamed name: String) {
        guard let item = library.playlist(named: name)?.items.first else { return }
        play(item)
    }
}
