class Engine {
    public fun start(): Int = 0
}

class Car {
    public fun go(engine: Engine): Int {
        return engine.start()
    }
}
