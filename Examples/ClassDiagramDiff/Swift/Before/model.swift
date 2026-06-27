class Account {}

class User: Account {
    var name: String
}

class AdminUser: User {}

class OrderService {
    func place() {}
}

class PaymentGateway {}

class LegacyAudit {
    func review() {}
}
