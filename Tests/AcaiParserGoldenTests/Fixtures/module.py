"""Module scope: globals, freestanding functions, decorated functions, the main guard."""

import os
from typing import Optional

VERSION: str = "1.2.3"
RETRIES = 3
TIMEOUT: float = 2.5
DEBUG = False
DEFAULTS = {"a": 1}
MISSING: Optional[str] = None


class Settings:

    def __init__(self, name: str):
        self.name = name

    def describe(self) -> str:
        return self.name


def build_settings(name: str) -> Settings:
    return Settings(name)


def with_defaults(name: str = "default", *, retries: int = RETRIES) -> Settings:
    return build_settings(name)


async def load_settings(path: str) -> Settings:
    return build_settings(path)


def decorated_target():
    pass


@decorated_target
def decorated_function() -> None:
    pass


def branching_free_function(value: int) -> str:
    if value > 0 and value < 10:
        return "small"
    if value > 10 or value < -10:
        return "large"
    return "other"


if __name__ == "__main__":
    settings = build_settings(os.environ.get("NAME", "main"))
    print(settings.describe())
