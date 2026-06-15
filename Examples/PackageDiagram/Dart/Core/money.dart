/// A currency amount. Part of the `Core` module.
class Money {
  final double amount;
  final String currency;

  Money(this.amount, this.currency);

  Money adding(Money other) => Money(amount + other.amount, currency);
}
