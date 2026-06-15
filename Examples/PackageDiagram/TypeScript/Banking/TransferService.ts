import { Account } from "../Core/Account";
import { AccountRepository } from "../Core/AccountRepository";
import { Money } from "../Core/Money";

/** Moves money between accounts. Part of the `Banking` module; depends on `Core`. */
export class TransferService {
    constructor(private readonly repository: AccountRepository) {}

    transfer(amount: Money, source: string, destination: string): void {
        const sender = this.repository.find(source);
        const recipient = this.repository.find(destination);
        if (!sender || !recipient) {
            return;
        }
        sender.deposit(amount);
        recipient.deposit(amount);
        this.repository.save(sender);
        this.repository.save(recipient);
    }
}
