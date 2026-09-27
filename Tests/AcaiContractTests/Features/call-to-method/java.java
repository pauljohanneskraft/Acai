public class Engine {
    public int start() { return 0; }
}

public class Car {
    public int go(Engine engine) {
        return engine.start();
    }
}
