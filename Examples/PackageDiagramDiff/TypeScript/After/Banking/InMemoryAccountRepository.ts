import { Account } from "../Core/Account";
import { AccountRepository } from "../Core/AccountRepository";

/** An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`. */
export class InMemoryAccountRepository implements AccountRepository {
    private storage = new Map<string, Account>();

    find(id: string): Account | undefined {
        return this.storage.get(id);
    }

    save(account: Account): void {
        this.storage.set(account.id, account);
    }
}
