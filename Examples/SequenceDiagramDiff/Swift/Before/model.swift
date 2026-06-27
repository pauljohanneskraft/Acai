final class Checkout {
    private let payment: PaymentService
    init(payment: PaymentService) { self.payment = payment }
    func placeOrder() {
        payment.charge()
        payment.verify()
    }
}
final class PaymentService {
    func charge() {}
    func verify() {}
}
