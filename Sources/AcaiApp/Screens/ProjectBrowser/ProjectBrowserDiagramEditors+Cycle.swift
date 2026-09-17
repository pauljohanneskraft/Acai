import Foundation
import AcaiQuality
import AcaiRender

// Split out of `ProjectBrowserDiagramEditors.swift` purely to keep that file under SwiftLint's
// file-length limit — same rationale as this app's other `+<Topic>.swift` extension splits.
extension GeneratedDiagramEditor {
    /// Opens a dependency cycle (`AcaiQuality.CycleFinder.Cycle`) as a diagram scoped to exactly its
    /// members: a class diagram, filtered to `members` via `Selector.explicitIDs`, for a
    /// `.types`-scope cycle; a package diagram, filtered via `Selector.explicitModules`, for a
    /// `.modules`-scope one. The diagram's own layout engine then only draws edges between shown
    /// nodes, so this needs no separate edge-resolution step — the cycle's members are all that's
    /// pinned. Named after the cycle (frozen, like `createDiagramFromSelection`'s "… Selection")
    /// rather than the type's generic auto-name, so distinct cycles opened from the same codebase
    /// stay distinguishable.
    func openCycle(
        to projectID: UUID, codebaseID: UUID, scope: CycleFinder.Scope, members: [String]
    ) -> UUID? {
        let memberSet = Set(members)
        let content: GeneratedDiagram.Content
        switch scope {
        case .types:
            var config = ClassDiagramConfiguration()
            config.filter = AcaiQuality.Selector(explicitIDs: memberSet)
            content = .classDiagram(config)
        case .modules:
            content = .packageDiagram
        }
        guard let id = add(to: projectID, codebaseID: codebaseID, content: content) else { return nil }
        if scope == .modules {
            updatePackageDiagramFilter(diagramID: id, filter: AcaiQuality.Selector(explicitModules: memberSet))
        }
        let codebasePrefix = codebaseName(codebaseID)
        let prefix = codebasePrefix.isEmpty ? "" : "\(codebasePrefix) — "
        let shown = members.prefix(3).joined(separator: " ↔ ")
        let suffix = members.count > 3 ? "…" : ""
        rename(id, name: "\(prefix)Cycle: \(shown)\(suffix)")
        return id
    }
}
