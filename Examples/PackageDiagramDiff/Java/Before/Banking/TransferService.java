/** Moves money between accounts. Part of the `Banking` module; depends on `Core`. */
final class TransferService {
    private final AccountRepository repository;

    TransferService(AccountRepository repository) {
        this.repository = repository;
    }

    void transfer(Money amount, String source, String destination) {
        Account sender = repository.find(source);
        Account recipient = repository.find(destination);
        if (sender == null || recipient == null) {
            return;
        }
        sender.deposit(amount);
        recipient.deposit(amount);
        repository.save(sender);
        repository.save(recipient);
    }
}
