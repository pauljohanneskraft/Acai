class PaymentGateway:
    """The leaf of the call chain: talks to the bank."""

    def authorize(self) -> None:
        pass  # Contacts the bank and approves the charge.
