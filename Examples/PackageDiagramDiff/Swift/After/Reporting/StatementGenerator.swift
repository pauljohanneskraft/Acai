/// Generates account statements. Part of the `Reporting` module; depends on `Core`.
final class StatementGenerator {
    private let account: Account

    init(account: Account) {
        self.account = account
    }
}
