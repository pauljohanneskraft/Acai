protocol SpecDetector {
    func isPresent(at path: String) -> Bool
    func discoverSpecs(at path: String) -> [String]
}

struct SpecDiscovery {
    let detectors: [any SpecDetector]
    let fallback: any SpecDetector

    func discoverSpecs(in path: String) -> [String] {
        var specs: [String] = []
        for detector in detectors where detector.isPresent(at: path) {
            specs.append(contentsOf: detector.discoverSpecs(at: path))
        }
        if specs.isEmpty {
            specs = fallback.discoverSpecs(at: path)
        }
        return specs
    }
}

struct FallbackSpecDetector: SpecDetector {
    private let log: ChangeLog

    init(log: ChangeLog) {
        self.log = log
    }

    func isPresent(at path: String) -> Bool {
        !path.isEmpty
    }

    func discoverSpecs(at path: String) -> [String] {
        log.append("falling back for \(path)")
        return [path]
    }
}
