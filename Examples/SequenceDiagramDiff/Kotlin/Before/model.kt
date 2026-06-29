class Checkout(private val payment: PaymentService) {
    fun placeOrder() {
        payment.charge()
        payment.verify()
    }
}
class PaymentService {
    fun charge() {}
    fun verify() {}
}
