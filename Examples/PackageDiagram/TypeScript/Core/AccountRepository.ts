import { Account } from "./Account";

/** Persistence boundary for `Account`s. The abstraction in the `Core` module. */
export interface AccountRepository {
    find(id: string): Account | undefined;
    save(account: Account): void;
}
