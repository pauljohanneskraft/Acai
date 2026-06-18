from enum import Enum
from typing import Protocol


class Playable(Protocol):
    """Anything the player knows how to play."""

    @property
    def title(self) -> str: ...

    @property
    def duration(self) -> float: ...

    def play(self) -> None: ...


class Genre(Enum):
    """A coarse classification for a piece of media."""

    POP = "pop"
    ROCK = "rock"
    JAZZ = "jazz"
    CLASSICAL = "classical"
    ELECTRONIC = "electronic"
    SPOKEN_WORD = "spokenWord"
