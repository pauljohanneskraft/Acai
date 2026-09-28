struct DocumentStore {
    private var documents: [String] = []

    func save() -> Bool {
        validate()
    }

    func validate() -> Bool {
        !documents.isEmpty
    }

    func purge() {
        print(documents.count)
    }
}
