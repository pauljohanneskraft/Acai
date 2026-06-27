final class Checkout {
    private let payment: PaymentService
    private let audit: AuditService
    init(payment: PaymentService, audit: AuditService) {
        self.payment = payment
        self.audit = audit
    }
    func placeOrder() {
        payment.charge()
        audit.log()
    }
}
final class PaymentService {
    func charge() {}
    func verify() {}
}
final class AuditService {
    func log() {}
}
