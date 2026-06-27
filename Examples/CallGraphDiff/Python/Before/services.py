from orders import Order


class OrderService:
    """Places an order by charging payment and persisting it."""

    def __init__(self, payment: "PaymentService", repository: "OrderRepository"):
        self.payment: PaymentService = payment
        self.repository: OrderRepository = repository

    def place(self, order: Order) -> None:
        self.payment.charge(order)


class PaymentService:
    def charge(self, order: Order) -> None:
        pass


class OrderRepository:
    def save(self, order: Order) -> None:
        pass
