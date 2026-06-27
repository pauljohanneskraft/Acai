class Checkout(private val payment: PaymentService, private val audit: AuditService) {
    fun placeOrder() {
        payment.charge()
        audit.log()
    }
}
class PaymentService {
    fun charge() {}
    fun verify() {}
}
class AuditService {
    fun log() {}
}
