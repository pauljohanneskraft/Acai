import Foundation

/// The user's whole collection: every playlist in one place.
public final class Library {
    public private(set) var playlists: [Playlist]

    public init(playlists: [Playlist] = []) {
        self.playlists = playlists
    }

    public func addPlaylist(_ playlist: Playlist) {
        playlists.append(playlist)
    }

    public func playlist(named name: String) -> Playlist? {
        playlists.first { $0.name == name }
    }
}
