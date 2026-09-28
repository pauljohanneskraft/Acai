public class Base {
    public func rank() -> Int { 0 }
}

public class Sub: Base {
    public override func rank() -> Int { 1 }
}
