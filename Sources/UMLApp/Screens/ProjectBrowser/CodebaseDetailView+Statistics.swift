import SwiftUI
import UMLCore

// Drill-down list construction and Finder-reveal helpers for the statistics cards. Kept in a separate
// file (same module) so `CodebaseDetailView.swift` stays within SwiftLint's `file_length`.
extension CodebaseDetailView {

    /// Types ranked by the metric (descending, value > 0), each row revealing the type's file.
    func typeDetail(
        _ title: String, _ description: String, _ types: [CodeMetrics.TypeMetric],
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
                    value: "\(metric[keyPath: keyPath])", reveal: typeReveal(metric.id))
            }
        return StatisticDetail(title: title, description: description, rows: rows)
    }

    /// Modules ranked by instability (descending), each row revealing the module's directory.
    func moduleDetail(
        _ title: String, _ description: String, _ modules: [CodeMetrics.ModuleCoupling]
    ) -> StatisticDetail {
        let rows = modules
            .sorted { $0.instability != $1.instability ? $0.instability > $1.instability : $0.name < $1.name }
            .map { module in
                StatisticDetail.Row(
                    id: module.name, name: module.name,
                    value: String(format: "%.0f%%", module.instability * 100), reveal: moduleReveal(module.name))
            }
        return StatisticDetail(title: title, description: description, rows: rows)
    }

    /// The last `.`-separated segment of a qualified type name, for a compact caption.
    func shortName(_ qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }

    private func typeReveal(_ id: String) -> (() -> Void)? {
        guard let location = artifact.flatMap({ location(forTypeID: id, in: $0) }), let codebase
        else { return nil }
        return { revealInFinder(relativePath: location.filePath, codebase: codebase) }
    }

    private func moduleReveal(_ name: String) -> (() -> Void)? {
        guard let directory = moduleDirectory(named: name), let codebase else { return nil }
        return { revealInFinder(relativePath: directory, codebase: codebase) }
    }

    /// The source location of a (possibly nested) type by its canonical id — looked up in the
    /// flattened type space the metrics are computed over.
    private func location(forTypeID id: String, in artifact: CodeArtifact) -> SourceLocation? {
        artifact.flattened().first { $0.id == id }?.location
    }

    /// The relative directory path of a module: a representative type's path truncated at the module
    /// component (e.g. `Sources/UMLCore/Foo/Bar.swift` → `Sources/UMLCore`), or the file's parent.
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

    private func revealInFinder(relativePath: String, codebase: Codebase) {
        #if os(macOS)
        let url = URL(filePath: codebase.directoryPath).appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
