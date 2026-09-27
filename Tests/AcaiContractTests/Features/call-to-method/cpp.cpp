class Engine {
public:
    int start();
};

class Car {
public:
    int go(Engine engine) {
        return engine.start();
    }
};
