/** An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`. */
class InMemoryAccountRepository : AccountRepository {
    private val storage: MutableMap<String, Account> = mutableMapOf()

    override fun find(id: String): Account? = storage[id]

    override fun save(account: Account) {
        storage[account.id] = account
    }
}
