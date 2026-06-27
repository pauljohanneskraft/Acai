class Account {}

class User extends Account {
  String name = "";
}

class AdminUser extends User {}

class OrderService {
  void place() {}
}

class PaymentGateway {}

class LegacyAudit {
  void review() {}
}
