public class Base {
    public var id: String = "idle"

    public init() {}

    public func run() {
        id = "requested"
        id = "running"
        id = "finished"
    }

    public func fail() {
        id = "failed"
    }
}
