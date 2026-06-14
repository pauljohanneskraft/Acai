/// Entry point: placing an order drives the whole payment sequence.
class Checkout {
  final PaymentService payment;

  Checkout(this.payment);

  void placeOrder() {
    payment.charge();
  }
}
