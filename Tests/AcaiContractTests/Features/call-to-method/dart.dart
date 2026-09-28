class Engine {
  int start() => 0;
}

class Car {
  int go(Engine engine) {
    return engine.start();
  }
}
