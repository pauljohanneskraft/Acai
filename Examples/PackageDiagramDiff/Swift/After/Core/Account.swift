/// A bank account holding a balance. Part of the `Core` module.
class Account {
    let id: String
    private(set) var balance: Money

    init(id: String, balance: Money) {
        self.id = id
        self.balance = balance
    }

    func deposit(_ amount: Money) {
        balance = balance.adding(amount)
    }
}
