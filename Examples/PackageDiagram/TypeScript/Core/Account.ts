import { Money } from "./Money";

/** A bank account holding a balance. Part of the `Core` module. */
export class Account {
    constructor(readonly id: string, private balance: Money) {}

    deposit(amount: Money): void {
        this.balance = this.balance.adding(amount);
    }
}
