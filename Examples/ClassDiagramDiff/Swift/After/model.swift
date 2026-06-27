class Account {}

class User {
    var name: String
    var email: String
}

class AdminUser: User {}

class OrderService {
    var gateway: PaymentGateway
    func place() {}
}

class PaymentGateway {}

class Receipt {
    var total: String
}
