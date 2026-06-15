/** A currency amount. Part of the `Core` module. */
final class Money {
    final double amount;
    final String currency;

    Money(double amount, String currency) {
        this.amount = amount;
        this.currency = currency;
    }

    Money adding(Money other) {
        return new Money(amount + other.amount, currency);
    }
}
