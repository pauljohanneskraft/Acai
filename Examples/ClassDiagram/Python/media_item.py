from playable import Genre, Playable


class MediaItem(Playable):
    """Shared base for every item in the library."""

    def __init__(self, title: str, duration: float, genre: Genre):
        self.title: str = title
        self.duration: float = duration
        self.genre: Genre = genre

    def play(self) -> None:
        print(f"Playing {self.title}…")
