class Checkout:
    def __init__(self, payment: "PaymentService"):
        self.payment: PaymentService = payment

    def placeOrder(self):
        self.payment.charge()
        self.payment.verify()


class PaymentService:
    def charge(self):
        pass

    def verify(self):
        pass
