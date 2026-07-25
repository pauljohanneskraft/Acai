public class Derived: Base {
    private let helper = Helper()

    public func doWork() {
        helper.performTask()
    }
}
