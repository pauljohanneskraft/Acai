"""Type-annotation shapes: the resolver's unions, wrappers, forward refs and generics."""

from typing import Annotated, Any, ClassVar, Dict, Final, List, Optional, Set, Tuple, Union


class Engine:

    def start(self) -> None:
        pass


class Wheel:
    pass


class Annotations:

    registry: ClassVar[Dict[str, "Engine"]] = {}
    limit: Final[int] = 10

    def __init__(self):
        self.engine: Engine = Engine()
        self.spare: Optional[Wheel] = None
        self.wheels: List[Wheel] = []
        self.lookup: Dict[str, Wheel] = {}
        self.pair: Tuple[Engine, Wheel] = (Engine(), Wheel())
        self.tags: Set[str] = set()
        self.anything: Any = None

    def optional_old(self, value: Optional[Engine]) -> Optional[Wheel]:
        return None

    def union_old(self, value: Union[Engine, Wheel]) -> Union[int, str]:
        return 0

    def union_new(self, value: Engine | Wheel) -> int | None:
        return None

    def nested_optional(self, value: Optional[List[Optional[Engine]]]) -> None:
        pass

    def annotated(self, value: Annotated[Engine, "meta"]) -> None:
        pass

    def forward(self, value: "Engine") -> "Wheel":
        return Wheel()

    def deeply_nested(self, value: Dict[str, List[Tuple[Engine, Optional[Wheel]]]]) -> None:
        pass

    def no_annotation(self, value):
        return value

    def primitives(self, a: int, b: float, c: str, d: bool, e: bytes) -> None:
        pass


def generic_function[V](value: V) -> V:
    return value


class Container[K, V]:

    def __init__(self):
        self.items: Dict[K, V] = {}

    def get(self, key: K) -> Optional[V]:
        return self.items.get(key)
