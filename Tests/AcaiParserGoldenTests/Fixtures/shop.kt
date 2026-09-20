package com.example.shop

interface Priced {
    fun price(): Double
}

abstract class Item(val name: String) : Priced {
    abstract override fun price(): Double
    open fun describe(): String = name
}

enum class Category(val label: String) {
    FOOD("food"),
    TOOL("tool")
}

data class Money(val amount: Double, val currency: String = "EUR")

class Product(name: String, private val base: Double) : Item(name) {

    var discount: Double = 0.0
    private val audit: Logger = Logger()

    class Builder {
        var name: String = ""
        fun build(): Product = Product(name, 0.0)
    }

    companion object {
        fun empty(): Product = Product("", 0.0)
    }

    override fun price(): Double {
        audit.log("pricing")
        return base - discount
    }

    override fun describe(): String {
        val money = Money(price(), "EUR")
        return "$name ${money.amount}"
    }

    fun classify(value: Int): Category {
        if (value > 10) {
            return Category.TOOL
        } else if (value > 5) {
            return Category.FOOD
        }
        for (index in 0 until value) {
            discount += index
        }
        return Category.FOOD
    }
}

class Logger {
    fun log(message: String) {}
}

fun topLevelDiscount(product: Product): Double = product.price()

val DEFAULT_CURRENCY: String = "EUR"
