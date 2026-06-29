class Account {}

class User extends Account {
    name: string = "";
}

class AdminUser extends User {}

class OrderService {
    place(): void {}
}

class PaymentGateway {}

class LegacyAudit {
    review(): void {}
}
