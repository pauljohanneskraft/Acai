class Account:
    pass


class User(Account):
    def __init__(self):
        self.name: str = ""


class AdminUser(User):
    pass


class OrderService:
    def place(self):
        pass


class PaymentGateway:
    pass


class LegacyAudit:
    def review(self):
        pass
