from playlist import Playlist


class Library:
    """The user's whole collection: every playlist in one place."""

    def __init__(self, playlists: list[Playlist] | None = None):
        self.playlists: list[Playlist] = playlists if playlists is not None else []

    def addPlaylist(self, playlist: Playlist) -> None:
        self.playlists.append(playlist)

    def playlist(self, named: str) -> Playlist | None:
        for playlist in self.playlists:
            if playlist.name == named:
                return playlist
        return None
