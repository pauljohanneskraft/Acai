/// Places an order by charging payment and persisting it.
class OrderService {
    let payment: PaymentService
    let repository: OrderRepository

    init(payment: PaymentService, repository: OrderRepository) {
        self.payment = payment
        self.repository = repository
    }

    func place(_ order: Order) {
        payment.charge(order)
        repository.save(order)
    }
}

class PaymentService {
    func charge(_ order: Order) {}
}

class OrderRepository {
    func save(_ order: Order) {}
}
