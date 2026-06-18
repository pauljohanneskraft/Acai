from PaymentService import PaymentService


class Checkout:
    """Entry point: placing an order drives the whole payment sequence."""

    def __init__(self, payment: PaymentService):
        self.payment: PaymentService = payment

    def placeOrder(self) -> None:
        self.payment.charge()
