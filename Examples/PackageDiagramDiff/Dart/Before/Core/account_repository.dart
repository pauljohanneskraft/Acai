/// Persistence boundary for `Account`s. The abstraction in the `Core` module.
abstract class AccountRepository {
  Account? find(String id);

  void save(Account account);
}
