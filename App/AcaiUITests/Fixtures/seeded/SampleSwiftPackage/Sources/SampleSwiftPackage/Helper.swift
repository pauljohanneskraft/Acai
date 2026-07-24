public class Helper {
    private let worker = Worker()

    public func performTask() {
        worker.execute()
    }
}
