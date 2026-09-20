#include <string>
#include <vector>

namespace shop {

enum class Category {
    Food,
    Tool
};

struct Money {
    double amount;
    std::string currency;
};

class Logger {
public:
    void log(const std::string &message);
};

class Priced {
public:
    virtual double price() const = 0;
    virtual ~Priced() = default;
};

class Item : public Priced {
protected:
    std::string name;

public:
    explicit Item(const std::string &name);
    virtual std::string describe() const;
};

class Product : public Item {
private:
    Logger audit;
    double base;
    std::vector<std::string> tags;

public:
    double discount;
    static const std::string defaultCurrency;

    class Builder {
    public:
        Product build() const;
    };

    Product(const std::string &name, double base);

    double price() const override {
        return base - discount;
    }

    std::string describe() const override {
        return name;
    }

    Category classify(int value) {
        if (value > 10) {
            return Category::Tool;
        } else if (value > 5) {
            return Category::Food;
        }
        for (int index = 0; index < value; ++index) {
            discount += index;
        }
        return Category::Food;
    }

    template <typename T>
    T identity(T value) const {
        return value;
    }
};

double topLevelDiscount(const Product &product) {
    return product.price();
}

}  // namespace shop
