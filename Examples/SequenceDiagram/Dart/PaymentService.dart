/// Charges an order by delegating to the payment gateway.
class PaymentService {
  final PaymentGateway gateway;

  PaymentService(this.gateway);

  void charge() {
    gateway.authorize();
  }
}
