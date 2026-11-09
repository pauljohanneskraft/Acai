from typing import Protocol


class Playable(Protocol):
    def play(self) -> bool:
        ...


class Song(Playable):
    pass
