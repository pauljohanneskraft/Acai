package shop

/** Entry point: placing an order drives the whole payment sequence. */
class Checkout(private val payment: PaymentService) {
    fun placeOrder() {
        payment.charge()
    }
}
