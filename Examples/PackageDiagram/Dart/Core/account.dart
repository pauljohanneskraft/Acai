/// A bank account holding a balance. Part of the `Core` module.
class Account {
  final String id;
  Money balance;

  Account(this.id, this.balance);

  void deposit(Money amount) {
    balance = balance.adding(amount);
  }
}
