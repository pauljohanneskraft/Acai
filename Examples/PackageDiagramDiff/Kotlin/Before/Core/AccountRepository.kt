/** Persistence boundary for `Account`s. The abstraction in the `Core` module. */
interface AccountRepository {
    fun find(id: String): Account?
    fun save(account: Account)
}
