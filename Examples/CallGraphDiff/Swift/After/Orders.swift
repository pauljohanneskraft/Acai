struct Order {
    let id: String
}

/// Entry point: fans out to validation and order placement.
class OrderController {
    let service: OrderService
    let validator: Validator

    init(service: OrderService, validator: Validator) {
        self.service = service
        self.validator = validator
    }

    func submit(order: Order) {
        validator.validate(order)
        service.place(order)
    }
}

class Validator {
    func validate(_ order: Order) {}
}
