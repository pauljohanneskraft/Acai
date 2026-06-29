/** Entry point: fans out to validation and order placement. */
class OrderController {
    private final OrderService service;
    private final Validator validator;

    OrderController(OrderService service, Validator validator) {
        this.service = service;
        this.validator = validator;
    }

    void submit(Order order) {
        validator.validate(order);
        service.place(order);
    }
}
