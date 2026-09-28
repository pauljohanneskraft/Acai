from typing import override


class Base:
    def rank(self) -> int:
        return 0


class Sub(Base):
    @override
    def rank(self) -> int:
        return 1
