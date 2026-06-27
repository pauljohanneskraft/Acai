from money import Money


class Account:
    """A bank account holding a balance. Part of the ``Core`` module."""

    def __init__(self, id: str, balance: Money):
        self.id: str = id
        self.balance: Money = balance

    def deposit(self, amount: Money) -> None:
        self.balance = self.balance.adding(amount)
