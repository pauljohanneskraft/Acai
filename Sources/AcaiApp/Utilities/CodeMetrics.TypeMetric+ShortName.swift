import AcaiCore

extension CodeMetrics.TypeMetric {
    var shortName: String {
        name.split(separator: ".").last.map(String.init) ?? name
    }
}
