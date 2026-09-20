#include <stdlib.h>

typedef enum {
    CATEGORY_FOOD,
    CATEGORY_TOOL
} Category;

typedef struct {
    double amount;
    char currency[4];
} Money;

struct Logger {
    int level;
};

struct Product {
    const char *name;
    double base;
    double discount;
    struct Logger audit;
};

static double product_price(struct Product *product) {
    return product->base - product->discount;
}

Category product_classify(struct Product *product, int value) {
    if (value > 10) {
        return CATEGORY_TOOL;
    } else if (value > 5) {
        return CATEGORY_FOOD;
    }
    for (int index = 0; index < value; index++) {
        product->discount += index;
    }
    return CATEGORY_FOOD;
}

struct Product *product_create(const char *name, double base) {
    struct Product *product = malloc(sizeof(struct Product));
    product->name = name;
    product->base = base;
    product->discount = 0.0;
    return product;
}

double top_level_discount(struct Product *product) {
    return product_price(product);
}
