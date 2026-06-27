/// Persistence boundary for `Account`s. The abstraction in the `Core` module.
protocol AccountRepository {
    func find(id: String) -> Account?
    func save(_ account: Account)
}
