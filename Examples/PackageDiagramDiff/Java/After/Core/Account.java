/** A bank account holding a balance. Part of the `Core` module. */
final class Account {
    final String id;
    private Money balance;

    Account(String id, Money balance) {
        this.id = id;
        this.balance = balance;
    }

    void deposit(Money amount) {
        balance = balance.adding(amount);
    }
}
