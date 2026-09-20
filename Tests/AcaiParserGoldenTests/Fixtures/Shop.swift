import Foundation

protocol Priced {
    func price() -> Double
}

enum Category: String {
    case food
    case tool
}

struct Money {
    var amount: Double
    var currency: String = "EUR"
}

final class Logger {
    func log(_ message: String) {}
}

class Item: Priced {

    let name: String

    init(name: String) {
        self.name = name
    }

    func price() -> Double { 0 }

    func describe() -> String { name }
}

final class Product: Item {

    struct Builder {
        var name: String = ""
        func build() -> Product { Product(name: name, base: 0) }
    }

    private let audit = Logger()
    private var base: Double
    var discount: Double = 0
    private(set) var tags: [String] = []
    static let defaultCurrency = "EUR"

    init(name: String, base: Double) {
        self.base = base
        super.init(name: name)
    }

    override func price() -> Double {
        audit.log("pricing")
        return base - discount
    }

    override func describe() -> String {
        let local = Logger()
        local.log(name)
        return name
    }

    func classify(value: Int) -> Category {
        if value > 10 {
            return .tool
        } else if value > 5 {
            return .food
        }
        for index in 0..<value {
            discount += Double(index)
        }
        return .food
    }

    var isFree: Bool { base == 0 }

    func identity<T>(_ value: T) -> T { value }
}

extension Product {
    func shortLabel() -> String { describe() }
}

func topLevelDiscount(_ product: Product) -> Double {
    product.price()
}

let kDefaultCurrency = "EUR"
