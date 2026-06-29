class Order:
    def __init__(self, id: str):
        self.id: str = id


class OrderController:
    """Entry point: fans out to validation and order placement."""

    def __init__(self, service: "OrderService", validator: "Validator"):
        self.service: OrderService = service
        self.validator: Validator = validator

    def submit(self, order: Order) -> None:
        self.validator.validate(order)
        self.service.place(order)


class Validator:
    def validate(self, order: Order) -> None:
        pass
