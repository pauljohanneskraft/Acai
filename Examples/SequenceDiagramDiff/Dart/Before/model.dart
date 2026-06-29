class Checkout {
  final PaymentService payment;
  Checkout(this.payment);
  void placeOrder() {
    payment.charge();
    payment.verify();
  }
}
class PaymentService {
  void charge() {}
  void verify() {}
}
