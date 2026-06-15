data class Order(val id: String)

/** Entry point: fans out to validation and order placement. */
class OrderController(private val service: OrderService, private val validator: Validator) {
    fun submit(order: Order) {
        validator.validate(order)
        service.place(order)
    }
}

class Validator {
    fun validate(order: Order) {}
}
