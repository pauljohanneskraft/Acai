/// Charges an order by delegating to the payment gateway.
public final class PaymentService {
    private let gateway: PaymentGateway

    public init(gateway: PaymentGateway) {
        self.gateway = gateway
    }

    public func charge() {
        gateway.authorize()
    }
}
