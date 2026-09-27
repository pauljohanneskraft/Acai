final class ScreenModel {
    let store: DocumentStore
    private let index: DocumentIndex
    private let log: ChangeLog

    init(store: DocumentStore, index: DocumentIndex, log: ChangeLog) {
        self.store = store
        self.index = index
        self.log = log
    }

    func persistChanges() {
        store.save()
        index.rebuild()
    }

    func reload() {
        let count = index.entryCount()
        log.append("reloaded \(count)")
    }

    func describe(using reporter: Reporter) {
        reporter.report("screen")
    }

    func purgeAll() {
        store.purge()
        log.flush()
    }
}
