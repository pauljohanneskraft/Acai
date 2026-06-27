/// A currency amount. Part of the `Core` module.
struct Money {
    let amount: Double
    let currency: String

    func adding(_ other: Money) -> Money {
        Money(amount: amount + other.amount, currency: currency)
    }
}
