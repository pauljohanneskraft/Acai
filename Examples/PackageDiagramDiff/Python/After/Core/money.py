class Money:
    """A currency amount. Part of the ``Core`` module."""

    def __init__(self, amount: float, currency: str):
        self.amount: float = amount
        self.currency: str = currency

    def adding(self, other: "Money") -> "Money":
        return Money(self.amount + other.amount, self.currency)
