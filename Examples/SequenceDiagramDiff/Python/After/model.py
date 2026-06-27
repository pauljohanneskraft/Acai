class Checkout:
    def __init__(self, payment: "PaymentService", audit: "AuditService"):
        self.payment: PaymentService = payment
        self.audit: AuditService = audit

    def placeOrder(self):
        self.payment.charge()
        self.audit.log()


class PaymentService:
    def charge(self):
        pass

    def verify(self):
        pass


class AuditService:
    def log(self):
        pass
