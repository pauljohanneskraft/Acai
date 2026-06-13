import { PaymentService } from "./PaymentService";

/** Entry point: placing an order drives the whole payment sequence. */
export class Checkout {
    constructor(private readonly payment: PaymentService) {}

    placeOrder(): void {
        this.payment.charge();
    }
}
