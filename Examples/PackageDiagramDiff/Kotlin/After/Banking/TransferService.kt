/** Moves money between accounts. Part of the `Banking` module; depends on `Core`. */
class TransferService(private val repository: AccountRepository) {
    fun transfer(amount: Money, source: String, destination: String) {
        val sender = repository.find(source) ?: return
        val recipient = repository.find(destination) ?: return
        sender.deposit(amount)
        recipient.deposit(amount)
        repository.save(sender)
        repository.save(recipient)
    }
}
