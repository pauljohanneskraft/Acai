/** Places an order by charging payment and persisting it. */
class OrderService {
    private final PaymentService payment;
    private final OrderRepository repository;

    OrderService(PaymentService payment, OrderRepository repository) {
        this.payment = payment;
        this.repository = repository;
    }

    void place(Order order) {
        payment.charge(order);
        repository.save(order);
    }
}
