class Checkout {
  final PaymentService payment;
  final AuditService audit;
  Checkout(this.payment, this.audit);
  void placeOrder() {
    payment.charge();
    audit.log();
  }
}
class PaymentService {
  void charge() {}
  void verify() {}
}
class AuditService {
  void log() {}
}
