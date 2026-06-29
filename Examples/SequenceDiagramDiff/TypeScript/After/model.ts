class Checkout {
    private payment: PaymentService;
    private audit: AuditService;
    placeOrder(): void {
        this.payment.charge();
        this.audit.log();
    }
}
class PaymentService {
    charge(): void {}
    verify(): void {}
}
class AuditService {
    log(): void {}
}
