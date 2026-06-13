/// Entry point: placing an order drives the whole payment sequence.
public final class Checkout {
    private let payment: PaymentService

    public init(payment: PaymentService) {
        self.payment = payment
    }

    public func placeOrder() {
        payment.charge()
    }
}
