class Account {}

class User {
    name: string = "";
    email: string = "";
}

class AdminUser extends User {}

class OrderService {
    gateway: PaymentGateway = new PaymentGateway();
    place(): void {}
}

class PaymentGateway {}

class Receipt {
    total: string = "";
}
