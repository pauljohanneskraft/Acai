open class Account

open class User {
    val name: String = ""
    val email: String = ""
}

class AdminUser : User()

class OrderService {
    val gateway: PaymentGateway = PaymentGateway()
    fun place() {}
}

class PaymentGateway

class Receipt {
    val total: String = ""
}
