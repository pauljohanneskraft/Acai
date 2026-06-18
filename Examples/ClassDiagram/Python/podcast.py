from media_item import MediaItem
from playable import Genre


class Podcast(MediaItem):
    """One episode of a podcast."""

    def __init__(self, title: str, duration: float, host: str, episodeNumber: int):
        super().__init__(title, duration, Genre.SPOKEN_WORD)
        self.host: str = host
        self.episodeNumber: int = episodeNumber

    def play(self) -> None:
        print(f"🎙 Episode {self.episodeNumber}: {self.title}")
