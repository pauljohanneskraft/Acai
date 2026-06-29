/// An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`.
class InMemoryAccountRepository implements AccountRepository {
  final Map<String, Account> _storage = {};

  @override
  Account? find(String id) => _storage[id];

  @override
  void save(Account account) {
    _storage[account.id] = account;
  }
}
