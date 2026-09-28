export class Engine {
    public start(): number { return 0 }
}

export class Car {
    public go(engine: Engine): number {
        return engine.start()
    }
}
