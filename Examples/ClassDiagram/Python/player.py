from library import Library
from playable import Playable


class Player:
    """Drives playback over a library. Depends on Library and the Playable interface."""

    def __init__(self, library: Library):
        self.library: Library = library
        self.nowPlaying: Playable | None = None

    def play(self, item: Playable) -> None:
        self.nowPlaying = item
        item.play()

    def playFirstItem(self, playlistNamed: str) -> None:
        playlist = self.library.playlist(playlistNamed)
        if playlist is not None and playlist.items:
            self.play(playlist.items[0])
