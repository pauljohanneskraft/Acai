export class Base {
    public rank(): number { return 0 }
}

export class Sub extends Base {
    public override rank(): number { return 1 }
}
