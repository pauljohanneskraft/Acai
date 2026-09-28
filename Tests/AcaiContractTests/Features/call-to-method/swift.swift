public class Engine {
    public func start() -> Int { 0 }
}

public class Car {
    public func go(engine: Engine) -> Int {
        return engine.start()
    }
}
