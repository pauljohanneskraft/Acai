from abc import ABC, abstractmethod

from account import Account


class AccountRepository(ABC):
    """Persistence boundary for ``Account``s. The abstraction in the ``Core`` module."""

    @abstractmethod
    def find(self, id: str) -> Account | None: ...

    @abstractmethod
    def save(self, account: Account) -> None: ...
