/** A currency amount. Part of the `Core` module. */
export class Money {
    constructor(readonly amount: number, readonly currency: string) {}

    adding(other: Money): Money {
        return new Money(this.amount + other.amount, this.currency);
    }
}
