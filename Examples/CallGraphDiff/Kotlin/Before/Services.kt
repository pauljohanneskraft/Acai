/** Places an order by charging payment and persisting it. */
class OrderService(private val payment: PaymentService, private val repository: OrderRepository) {
    fun place(order: Order) {
        payment.charge(order)
    }
}

class PaymentService {
    fun charge(order: Order) {}
}

class OrderRepository {
    fun save(order: Order) {}
}
