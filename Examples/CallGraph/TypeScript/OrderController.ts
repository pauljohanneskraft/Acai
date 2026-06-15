import { Order } from "./Order";
import { OrderService } from "./OrderService";
import { Validator } from "./Validator";

/** Entry point: fans out to validation and order placement. */
export class OrderController {
    constructor(
        private readonly service: OrderService,
        private readonly validator: Validator
    ) {}

    submit(order: Order): void {
        this.validator.validate(order);
        this.service.place(order);
    }
}
