library shop;

abstract class Priced {
  double price();
}

enum Category { food, tool }

mixin Auditable {
  void audit(String message) {}
}

class Logger {
  void log(String message) {}
}

abstract class Item implements Priced {
  final String name;

  Item(this.name);

  @override
  double price();

  String describe() => name;
}

class Product extends Item with Auditable {
  final Logger _audit = Logger();
  double base;
  double discount = 0;
  static const String defaultCurrency = 'EUR';

  Product(String name, this.base) : super(name);

  factory Product.empty() => Product('', 0);

  @override
  double price() {
    _audit.log('pricing');
    return base - discount;
  }

  @override
  String describe() {
    final local = Logger();
    local.log(name);
    return name;
  }

  Category classify(int value) {
    if (value > 10) {
      return Category.tool;
    } else if (value > 5) {
      return Category.food;
    }
    for (var index = 0; index < value; index++) {
      discount += index;
    }
    return Category.food;
  }

  bool get isFree => base == 0;

  set price2(double value) {
    base = value;
  }

  T identity<T>(T value) => value;
}

extension ProductDescription on Product {
  String shortLabel() => describe();
}

double topLevelDiscount(Product product) => product.price();

const String kDefaultCurrency = 'EUR';
