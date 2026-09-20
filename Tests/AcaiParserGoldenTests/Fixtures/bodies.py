"""Body analysis: call sites, assignments, field reads, local bindings, complexity."""

from typing import Optional


class Logger:

    def log(self, message: str) -> None:
        pass

    def flush(self) -> None:
        pass


class Cache:

    def __init__(self):
        self.entries = {}

    def store(self, key: str, value: str) -> None:
        self.entries[key] = value

    def lookup(self, key: str) -> Optional[str]:
        return self.entries.get(key)


class Repository:

    def make_cache(self) -> Cache:
        return Cache()

    def make_logger(self) -> Logger:
        return Logger()


class Service:

    def __init__(self, logger: Logger):
        self.logger = logger
        self.cache = Cache()
        self.repository = Repository()
        self.counter = 0
        self.name = "service"
        self.enabled = True
        self.ratio = 1.5
        self.nothing = None

    def uses_own_properties(self) -> None:
        self.logger.log("start")
        self.cache.store("k", "v")
        self.counter = self.counter + 1
        self.counter += 1
        self.name = "renamed"
        self.enabled = False

    def uses_self_dispatch(self) -> None:
        self.uses_own_properties()
        self.helper()

    def helper(self) -> None:
        pass

    def uses_parameter(self, other: Logger) -> None:
        other.log("from parameter")

    def uses_local_from_construction(self) -> None:
        local = Cache()
        local.store("a", "b")

    def uses_local_from_annotation(self) -> None:
        local: Logger = self.repository.make_logger()
        local.flush()

    def uses_local_from_method_return(self) -> None:
        produced = self.make_cache_like()
        produced.store("c", "d")

    def make_cache_like(self) -> Cache:
        return Cache()

    def uses_static_call(self) -> None:
        Cache().store("e", "f")
        Logger().log("static")

    def uses_unknown_receiver(self, opaque) -> None:
        opaque.whatever()

    def uses_external_type(self) -> None:
        Missing.method()

    def branching(self, value: int) -> int:
        total = 0
        if value > 10:
            total += 1
        elif value > 5:
            total += 2
        else:
            total -= 1
        for index in range(value):
            if index % 2 == 0:
                total += index
            while total > 100:
                total -= 10
        try:
            total = total // value
        except ZeroDivisionError:
            total = 0
        return total if total > 0 else -total

    def comprehension(self, values: list) -> list:
        return [self.transform(item) for item in values if item]

    def transform(self, item):
        return item

    def reads_fields(self) -> str:
        return f"{self.name}:{self.counter}:{self.ratio}"


class Untyped:

    def __init__(self):
        self.inferred = Cache()
        self.plain = 1

    def uses_inferred(self) -> None:
        self.inferred.store("g", "h")
