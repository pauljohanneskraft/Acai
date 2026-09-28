class Engine:
    def start(self) -> int:
        return 0


class Car:
    def go(self, engine: Engine) -> int:
        return engine.start()
