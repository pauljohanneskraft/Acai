open class Account

open class User : Account() {
    val name: String = ""
}

class AdminUser : User()

class OrderService {
    fun place() {}
}

class PaymentGateway

class LegacyAudit {
    fun review() {}
}
