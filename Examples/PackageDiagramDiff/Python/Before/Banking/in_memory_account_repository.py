from account import Account
from account_repository import AccountRepository


class InMemoryAccountRepository(AccountRepository):
    """An in-memory ``AccountRepository``. Part of the ``Banking`` module; depends on ``Core``."""

    def __init__(self):
        self._storage: dict[str, Account] = {}

    def find(self, id: str) -> Account | None:
        return self._storage.get(id)

    def save(self, account: Account) -> None:
        self._storage[account.id] = account
