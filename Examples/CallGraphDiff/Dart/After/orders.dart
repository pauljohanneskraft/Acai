class Order {
  final String id;

  Order(this.id);
}

/// Entry point: fans out to validation and order placement.
class OrderController {
  final OrderService service;
  final Validator validator;

  OrderController(this.service, this.validator);

  void submit(Order order) {
    validator.validate(order);
    service.place(order);
  }
}

class Validator {
  void validate(Order order) {}
}
