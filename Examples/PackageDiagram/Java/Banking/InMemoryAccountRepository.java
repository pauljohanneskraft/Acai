import java.util.HashMap;
import java.util.Map;

/** An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`. */
final class InMemoryAccountRepository implements AccountRepository {
    private final Map<String, Account> storage = new HashMap<>();

    public Account find(String id) {
        return storage.get(id);
    }

    public void save(Account account) {
        storage.put(account.id, account);
    }
}
