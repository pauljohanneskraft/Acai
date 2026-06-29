/// An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`.
final class InMemoryAccountRepository: AccountRepository {
    private var storage: [String: Account] = [:]

    func find(id: String) -> Account? {
        storage[id]
    }

    func save(_ account: Account) {
        storage[account.id] = account
    }
}
