class Account {}

class User {
    String name;
    String email;
}

class AdminUser extends User {}

class OrderService {
    PaymentGateway gateway;
    void place() {}
}

class PaymentGateway {}

class Receipt {
    String total;
}
