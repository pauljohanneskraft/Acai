/** Persistence boundary for `Account`s. The abstraction in the `Core` module. */
interface AccountRepository {
    Account find(String id);

    void save(Account account);
}
