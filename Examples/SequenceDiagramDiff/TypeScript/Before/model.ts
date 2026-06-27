class Checkout {
    private payment: PaymentService;
    placeOrder(): void {
        this.payment.charge();
        this.payment.verify();
    }
}
class PaymentService {
    charge(): void {}
    verify(): void {}
}
