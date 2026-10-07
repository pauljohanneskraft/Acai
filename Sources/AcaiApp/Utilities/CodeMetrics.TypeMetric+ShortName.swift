import AcaiCore

extension CodeMetrics.TypeMetric {
    /// The last segment of `name`, past a file-scoped id's `path:` prefix too, whose path has dots of its own.
    var shortName: String {
        let unscoped = name.split(separator: ":").last.map(String.init) ?? name
        return unscoped.split(separator: ".").last.map(String.init) ?? unscoped
    }
}
