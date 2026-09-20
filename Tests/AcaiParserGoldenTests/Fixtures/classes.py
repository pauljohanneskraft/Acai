"""Type-declaration shapes: kinds, bases, nesting, generics, decorators, access."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import Generic, Protocol, TypeVar

T = TypeVar("T")


class Colour(Enum):
    RED = "red"
    GREEN = "green"
    BLUE = "blue"


class Priority(IntEnum):
    LOW = 1
    HIGH = 2


@dataclass
class Money:
    amount: float
    currency: str = "EUR"

    def doubled(self) -> "Money":
        return Money(self.amount * 2, self.currency)


class Shape(ABC):

    @abstractmethod
    def area(self) -> float:
        ...

    @abstractmethod
    def perimeter(self) -> float:
        ...


class Rectangle(Shape):

    def __init__(self, width: float, height: float):
        self.width = width
        self.height = height
        self._cached_area = None

    def area(self) -> float:
        return self.width * self.height

    def perimeter(self) -> float:
        return 2 * (self.width + self.height)

    @property
    def is_square(self) -> bool:
        return self.width == self.height

    @staticmethod
    def unit() -> "Rectangle":
        return Rectangle(1.0, 1.0)

    @classmethod
    def square(cls, side: float) -> "Rectangle":
        return cls(side, side)


class Box(Generic[T]):

    def __init__(self, value: T):
        self.value = value

    def unwrap(self) -> T:
        return self.value


class Drawable(Protocol):

    def draw(self) -> None:
        ...


class Outer:

    class Inner:

        class Innermost:

            def depth(self) -> int:
                return 3

        def inner_method(self) -> str:
            return "inner"

    def outer_method(self) -> str:
        return "outer"


class Visibility:

    def public_method(self) -> None:
        pass

    def _protected_method(self) -> None:
        pass

    def __private_method(self) -> None:
        pass

    def __dunder__(self) -> None:
        pass


class Mixed(Rectangle, Drawable):

    def draw(self) -> None:
        pass


class ParameterShapes:

    def every_shape(self, plain, typed: int, defaulted: str = "x", *args, **kwargs) -> None:
        pass

    def typed_splats(self, *args: str, **kwargs: int) -> None:
        pass

    def keyword_only(self, first: int, *, second: int = 2) -> None:
        pass


class Modern[U]:

    def identity(self, value: U) -> U:
        return value


async def fetch_all() -> list:
    return []


class AsyncService:

    async def fetch(self, key: str) -> str:
        return key

    async def __aenter__(self) -> "AsyncService":
        return self
