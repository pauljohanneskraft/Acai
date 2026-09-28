struct ChangeLog {
    private var lines: [String] = []

    func append(_ message: String) {
        print(message)
    }

    func flush() {
        print(lines.count)
    }
}

struct Reporter {
    func report(_ text: String) {
        print(text)
    }
}
