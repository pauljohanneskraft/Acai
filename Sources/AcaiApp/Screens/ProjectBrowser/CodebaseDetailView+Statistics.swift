import SwiftUI
import AcaiCore

extension CodebaseDetailView {

    func typeDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ types: [CodeMetrics.TypeMetric],
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>
    ) -> StatisticDetail {
        let rows = types
            .filter { $0[keyPath: keyPath] > 0 }
            .sorted { lhs, rhs in
                let left = lhs[keyPath: keyPath], right = rhs[keyPath: keyPath]
                return left != right ? left > right : lhs.name < rhs.name
            }
            .map { metric in
                StatisticDetail.Row(
                    id: metric.id, name: shortName(metric.name),
                    value: metric[keyPath: keyPath].formatted(), relativePath: typeRelativePath(metric.id),
                    reference: .type(id: metric.id))
            }
        return StatisticDetail(title: title, description: description, rows: rows)
    }

    func typeDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ types: [CodeMetrics.TypeMetric],
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Double>, format: (Double) -> String
    ) -> StatisticDetail {
        let rows = types
            .filter { $0[keyPath: keyPath] > 0 }
            .sorted { lhs, rhs in
                let left = lhs[keyPath: keyPath], right = rhs[keyPath: keyPath]
                return left != right ? left > right : lhs.name < rhs.name
            }
            .map { metric in
                StatisticDetail.Row(
                    id: metric.id, name: shortName(metric.name),
                    value: format(metric[keyPath: keyPath]), relativePath: typeRelativePath(metric.id),
                    reference: .type(id: metric.id))
            }
        return StatisticDetail(title: title, description: description, rows: rows)
    }

    func moduleDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ modules: [CodeMetrics.ModuleCoupling],
        value: (CodeMetrics.ModuleCoupling) -> Double, format: (Double) -> String
    ) -> StatisticDetail {
        let rows = modules
            .filter { value($0) > 0 }
            .sorted { value($0) != value($1) ? value($0) > value($1) : $0.name < $1.name }
            .map { module in
                StatisticDetail.Row(
                    id: module.name, name: module.name,
                    value: format(value(module)), relativePath: moduleDirectory(named: module.name),
                    reference: .module(name: module.name))
            }
        return StatisticDetail(title: title, description: description, rows: rows)
    }

    func shortName(_ qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }

    private func typeRelativePath(_ id: String) -> String? {
        artifact.flatMap { location(forTypeID: id, in: $0) }?.filePath
    }

    /// Looked up in the flattened type space, since a type here may be nested.
    private func location(forTypeID id: String, in artifact: CodeArtifact) -> SourceLocation? {
        artifact.flattened().first { $0.id == id }?.location
    }

    /// The relative directory path of a module: a representative type's path truncated at the module
    /// component (e.g. `Sources/AcaiCore/Foo/Bar.swift` → `Sources/AcaiCore`), or the file's parent.
    private func moduleDirectory(named module: String) -> String? {
        let resolver = ModuleResolver.standard
        guard let artifact,
              let path = artifact.flattened().lazy.compactMap({ $0.location?.filePath })
                  .first(where: { resolver.productName(forFilePath: $0) == module })
        else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let index = parts.firstIndex(of: module) {
            return parts[...index].joined(separator: "/")
        }
        return parts.dropLast().joined(separator: "/")
    }
}
