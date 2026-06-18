from PaymentGateway import PaymentGateway


class PaymentService:
    """Charges an order by delegating to the payment gateway."""

    def __init__(self, gateway: PaymentGateway):
        self.gateway: PaymentGateway = gateway

    def charge(self) -> None:
        self.gateway.authorize()
