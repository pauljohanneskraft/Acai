import Foundation

/// What deleting the sidebar's selection asks the user to confirm.
enum SidebarDeletion {
    case project(Project)
    case codebase(Codebase)
    case diagram(SidebarDiagramDeletion)
}

struct SidebarDiagramDeletion: Equatable {
    enum Kind {
        case generated
        case freeform
    }

    let diagramID: UUID
    let name: String
    let kind: Kind
}

extension ProjectBrowserViewModel {
    /// Nil for a row the sidebar does not own (repository, findings, inspect) or one that no longer exists.
    var selectionDeletion: SidebarDeletion? {
        switch selection {
        case .project(let id):
            store.projects.first { $0.id == id }.map(SidebarDeletion.project)
        case .codebase(let id):
            codebase(for: id).map(SidebarDeletion.codebase)
        case .generatedDiagram(let id):
            generatedDiagram(for: id)
                .map { .diagram(SidebarDiagramDeletion(diagramID: $0.id, name: $0.name, kind: .generated)) }
        case .freeformDiagram(let id):
            freeformDiagram(for: id)
                .map { .diagram(SidebarDiagramDeletion(diagramID: $0.id, name: $0.name, kind: .freeform)) }
        case .repository, .findings, .inspect, .none:
            nil
        }
    }

    func delete(_ diagram: SidebarDiagramDeletion) {
        switch diagram.kind {
        case .generated:
            diagrams.remove(diagram.diagramID)
        case .freeform:
            freeforms.remove(diagram.diagramID)
        }
    }
}
