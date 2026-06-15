/** A currency amount. Part of the `Core` module. */
data class Money(val amount: Double, val currency: String) {
    fun adding(other: Money): Money = Money(amount + other.amount, currency)
}
