class Checkout {
    private PaymentService payment;
    void placeOrder() {
        payment.charge();
        payment.verify();
    }
}
class PaymentService {
    void charge() {}
    void verify() {}
}
