from account_repository import AccountRepository
from money import Money


class TransferService:
    """Moves money between accounts. Part of the ``Banking`` module; depends on ``Core``."""

    def __init__(self, repository: AccountRepository):
        self.repository: AccountRepository = repository

    def transfer(self, amount: Money, source: str, destination: str) -> None:
        sender = self.repository.find(source)
        recipient = self.repository.find(destination)
        if sender is None or recipient is None:
            return
        sender.deposit(amount)
        recipient.deposit(amount)
        self.repository.save(sender)
        self.repository.save(recipient)
