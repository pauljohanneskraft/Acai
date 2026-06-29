class Account:
    pass


class User:
    def __init__(self):
        self.name: str = ""
        self.email: str = ""


class AdminUser(User):
    pass


class OrderService:
    def __init__(self):
        self.gateway: PaymentGateway = PaymentGateway()

    def place(self):
        pass


class PaymentGateway:
    pass


class Receipt:
    def __init__(self):
        self.total: str = ""
