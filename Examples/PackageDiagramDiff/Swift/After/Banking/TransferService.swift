/// Moves money between accounts. Part of the `Banking` module; depends on `Core`.
final class TransferService {
    private let repository: AccountRepository

    init(repository: AccountRepository) {
        self.repository = repository
    }

    func transfer(amount: Money, from source: String, to destination: String) {
        guard let sender = repository.find(id: source),
            let recipient = repository.find(id: destination)
        else { return }
        sender.deposit(amount)
        recipient.deposit(amount)
        repository.save(sender)
        repository.save(recipient)
    }
}
