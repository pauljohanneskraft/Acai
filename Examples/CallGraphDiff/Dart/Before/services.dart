/// Places an order by charging payment and persisting it.
class OrderService {
  final PaymentService payment;
  final OrderRepository repository;

  OrderService(this.payment, this.repository);

  void place(Order order) {
    payment.charge(order);
  }
}

class PaymentService {
  void charge(Order order) {}
}

class OrderRepository {
  void save(Order order) {}
}
