import Foundation
import AcaiCore

/// Builds the flat `[QuickOpenEntry]` list Quick Open searches over, from a plain snapshot of the
/// store's data. A value you construct with that snapshot and ask to `entries()` — never a
/// static/namespace function — so it can run entirely off the main actor (`Task.detached`) in
/// `QuickOpenIndex`: building this over every project's every codebase's full artifact is the real
/// cost (debouncing keystrokes alone doesn't fix re-scanning everything on every search), not
/// something to redo synchronously on the main actor per query.
struct QuickOpenIndexBuilder: Sendable {
    var projects: [Project]
    /// Semantic artifacts keyed by codebase id — the same data `ProjectStore.artifacts` holds.
    var artifacts: [UUID: CodeArtifact]
    var generatedDiagrams: [UUID: GeneratedDiagram]
    var freeformDiagrams: [UUID: FreeformDiagram]

    func entries() -> [QuickOpenEntry] {
        var entries: [QuickOpenEntry] = []
        for project in projects {
            for codebase in project.codebases {
                entries += codebaseEntries(project: project, codebase: codebase)
            }
            for diagramID in project.generatedDiagramIDs {
                guard let diagram = generatedDiagrams[diagramID] else { continue }
                entries.append(QuickOpenEntry(
                    id: "generatedDiagram:\(diagramID)",
                    name: diagram.name,
                    kind: .generatedDiagram,
                    subtitle: project.title,
                    projectID: project.id,
                    codebaseID: diagram.codebaseID,
                    generatedDiagramID: diagramID
                ))
            }
            for diagramID in project.freeformDiagramIDs {
                guard let diagram = freeformDiagrams[diagramID] else { continue }
                entries.append(QuickOpenEntry(
                    id: "freeformDiagram:\(diagramID)",
                    name: diagram.name,
                    kind: .freeformDiagram,
                    subtitle: project.title,
                    projectID: project.id,
                    freeformDiagramID: diagramID
                ))
            }
        }
        return entries
    }

    private func codebaseEntries(project: Project, codebase: Codebase) -> [QuickOpenEntry] {
        guard let artifact = artifacts[codebase.id] else { return [] }
        var entries: [QuickOpenEntry] = []
        let types = artifact.flattened()
        var seenModules = Set<String>()
        for type in types {
            entries.append(QuickOpenEntry(
                id: "type:\(type.id)",
                name: type.name,
                kind: .type,
                subtitle: "\(project.title) — \(codebase.name)",
                projectID: project.id,
                codebaseID: codebase.id,
                reference: .type(id: type.id)
            ))
            for member in type.members where member.isMethod {
                entries.append(QuickOpenEntry(
                    id: "method:\(type.id).\(member.name)",
                    name: "\(type.name).\(member.name)",
                    kind: .method,
                    subtitle: "\(project.title) — \(codebase.name)",
                    projectID: project.id,
                    codebaseID: codebase.id,
                    reference: .method(typeName: type.name, methodName: member.name)
                ))
            }
            let module = ModuleResolver.standard.productName(forFilePath: type.location?.filePath ?? "")
            if seenModules.insert(module).inserted {
                entries.append(QuickOpenEntry(
                    id: "module:\(codebase.id):\(module)",
                    name: module,
                    kind: .module,
                    subtitle: "\(project.title) — \(codebase.name)",
                    projectID: project.id,
                    codebaseID: codebase.id,
                    reference: .module(name: module)
                ))
            }
        }
        return entries
    }
}
