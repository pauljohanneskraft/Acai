final class DocumentIndex {
    private var terms: [String: Int] = [:]

    func rebuild() {
        terms.removeAll()
    }

    func entryCount() -> Int {
        terms.count
    }
}
