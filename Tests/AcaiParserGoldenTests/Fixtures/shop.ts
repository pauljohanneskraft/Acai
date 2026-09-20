export interface Priced {
    price(): number;
}

export enum Category {
    Food = "food",
    Tool = "tool",
}

export type Money = {
    amount: number;
    currency: string;
};

export class Logger {
    log(message: string): void {}
}

export abstract class Item implements Priced {
    protected name: string;

    constructor(name: string) {
        this.name = name;
    }

    abstract price(): number;

    describe(): string {
        return this.name;
    }
}

export class Product extends Item {
    private audit: Logger = new Logger();
    public discount: number = 0;
    private tags: string[] = [];
    static defaultCurrency: string = "EUR";

    constructor(name: string, private base: number) {
        super(name);
    }

    price(): number {
        this.audit.log("pricing");
        return this.base - this.discount;
    }

    describe(): string {
        const local = new Logger();
        local.log(this.name);
        return this.name;
    }

    classify(value: number): Category {
        if (value > 10) {
            return Category.Tool;
        } else if (value > 5) {
            return Category.Food;
        }
        for (let index = 0; index < value; index++) {
            this.discount += index;
        }
        return Category.Food;
    }

    get isFree(): boolean {
        return this.base === 0;
    }

    identity<T>(value: T): T {
        return value;
    }
}

export function topLevelDiscount(product: Product): number {
    return product.price();
}

export const DEFAULT_CURRENCY: string = "EUR";
