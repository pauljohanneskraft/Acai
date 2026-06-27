/// Moves money between accounts. Part of the `Banking` module; depends on `Core`.
class TransferService {
  final AccountRepository repository;

  TransferService(this.repository);

  void transfer(Money amount, String source, String destination) {
    final sender = repository.find(source);
    final recipient = repository.find(destination);
    if (sender == null || recipient == null) {
      return;
    }
    sender.deposit(amount);
    recipient.deposit(amount);
    repository.save(sender);
    repository.save(recipient);
  }
}
