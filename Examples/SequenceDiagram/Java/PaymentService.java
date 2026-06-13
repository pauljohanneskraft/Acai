package shop;

/** Charges an order by delegating to the payment gateway. */
public final class PaymentService {
    private final PaymentGateway gateway;

    public PaymentService(PaymentGateway gateway) {
        this.gateway = gateway;
    }

    public void charge() {
        gateway.authorize();
    }
}
