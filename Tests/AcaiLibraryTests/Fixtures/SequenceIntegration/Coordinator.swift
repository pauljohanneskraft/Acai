final class Coordinator {
    private let screen: ScreenModel
    private let discovery: SpecDiscovery

    init(screen: ScreenModel, discovery: SpecDiscovery) {
        self.screen = screen
        self.discovery = discovery
    }

    func start() {
        screen.persistChanges()
        discovery.discoverSpecs(in: "/tmp")
    }

    func finish() {
        screen.purgeAll()
        let log = ChangeLog()
        log.flush()
    }
}
