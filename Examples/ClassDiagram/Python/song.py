from media_item import MediaItem
from playable import Genre


class Song(MediaItem):
    """A single track by an artist."""

    def __init__(self, title: str, duration: float, genre: Genre, artist: str, album: str | None = None):
        super().__init__(title, duration, genre)
        self.artist: str = artist
        self.album: str | None = album

    def play(self) -> None:
        print(f"♪ {self.artist} — {self.title}")
