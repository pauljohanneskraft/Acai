import { Order } from "./Order";
import { OrderRepository } from "./OrderRepository";
import { PaymentService } from "./PaymentService";

/** Places an order by charging payment and persisting it. */
export class OrderService {
    constructor(
        private readonly payment: PaymentService,
        private readonly repository: OrderRepository
    ) {}

    place(order: Order): void {
        this.payment.charge(order);
    }
}
