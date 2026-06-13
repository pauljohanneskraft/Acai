package shop

/** Charges an order by delegating to the payment gateway. */
class PaymentService(private val gateway: PaymentGateway) {
    fun charge() {
        gateway.authorize()
    }
}
