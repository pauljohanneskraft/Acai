class Logger {
    log(message) {}
}

class Item {
    constructor(name) {
        this.name = name;
    }

    describe() {
        return this.name;
    }
}

class Product extends Item {
    constructor(name, base) {
        super(name);
        this.audit = new Logger();
        this.base = base;
        this.discount = 0;
    }

    price() {
        this.audit.log("pricing");
        return this.base - this.discount;
    }

    describe() {
        const local = new Logger();
        local.log(this.name);
        return this.name;
    }

    classify(value) {
        if (value > 10) {
            return "tool";
        } else if (value > 5) {
            return "food";
        }
        for (let index = 0; index < value; index++) {
            this.discount += index;
        }
        return "food";
    }
}

function Legacy(name) {
    this.name = name;
}

Legacy.prototype.describe = function () {
    return this.name;
};

function topLevelDiscount(product) {
    return product.price();
}

const DEFAULT_CURRENCY = "EUR";
