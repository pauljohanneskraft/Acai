open class Base {
    public open fun rank(): Int = 0
}

class Sub : Base() {
    public override fun rank(): Int = 1
}
