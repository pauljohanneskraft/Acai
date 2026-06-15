/** A bank account holding a balance. Part of the `Core` module. */
class Account(val id: String, var balance: Money) {
    fun deposit(amount: Money) {
        balance = balance.adding(amount)
    }
}
