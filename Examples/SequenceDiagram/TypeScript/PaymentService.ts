import { PaymentGateway } from "./PaymentGateway";

/** Charges an order by delegating to the payment gateway. */
export class PaymentService {
    constructor(private readonly gateway: PaymentGateway) {}

    charge(): void {
        this.gateway.authorize();
    }
}
