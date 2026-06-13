package shop;

/** Entry point: placing an order drives the whole payment sequence. */
public final class Checkout {
    private final PaymentService payment;

    public Checkout(PaymentService payment) {
        this.payment = payment;
    }

    public void placeOrder() {
        payment.charge();
    }
}
