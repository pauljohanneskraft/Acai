from media_item import MediaItem


class Playlist:
    """An ordered collection of media items the user has curated."""

    def __init__(self, name: str, items: list[MediaItem] | None = None):
        self.name: str = name
        self.items: list[MediaItem] = items if items is not None else []

    @property
    def totalDuration(self) -> float:
        return sum(item.duration for item in self.items)

    def add(self, item: MediaItem) -> None:
        self.items.append(item)
