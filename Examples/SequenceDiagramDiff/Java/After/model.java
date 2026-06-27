class Checkout {
    private PaymentService payment;
    private AuditService audit;
    void placeOrder() {
        payment.charge();
        audit.log();
    }
}
class PaymentService {
    void charge() {}
    void verify() {}
}
class AuditService {
    void log() {}
}
