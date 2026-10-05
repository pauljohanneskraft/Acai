import SwiftUI
import AcaiCore
import AcaiRender

/// Edits the configuration of a generated class diagram and applies changes live.
///
/// `viewModel.configuration` is the single source of truth; `mutate` transforms a copy, then
/// persists it (`ProjectBrowserViewModel.updateClassDiagramConfiguration`) and applies it to
/// the live diagram (`ClassDiagramViewModel.applyConfiguration`, which rebuilds nodes/edges and
/// preserves layout when the grouping is unchanged). Shared by the settings inspector, the
/// per-node inspector, and the node context menu so all three stay consistent.
@MainActor
struct ClassDiagramConfigEditor {
    let model: ProjectBrowserViewModel
    let viewModel: ClassDiagramViewModel
    let diagramID: GeneratedDiagram.ID
    let artifact: CodeArtifact

    func mutate(_ transform: (inout ClassDiagramConfiguration) -> Void) {
        var configuration = viewModel.configuration
        transform(&configuration)
        model.diagrams.updateClassDiagramConfiguration(diagramID: diagramID, configuration: configuration)
        viewModel.applyConfiguration(configuration, artifact: artifact)
    }

    func clearEmptyScope(for reason: DiagramEmptyReason) {
        mutate { $0 = $0.widened(undoing: reason) }
    }

    /// Binding for a global visibility default. Flipping it also clears the matching per-type
    /// override map, so the toggle acts as a bulk reset for all individual type settings.
    func globalVisibility(
        _ defaultKeyPath: WritableKeyPath<ClassDiagramConfiguration, Bool>,
        override overrideKeyPath: WritableKeyPath<ClassDiagramConfiguration, [String: Bool]>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.configuration[keyPath: defaultKeyPath] },
            set: { newValue in
                mutate {
                    $0[keyPath: defaultKeyPath] = newValue
                    $0[keyPath: overrideKeyPath].removeAll()
                }
            }
        )
    }

    func typeVisibility(
        _ typeID: String,
        override overrideKeyPath: WritableKeyPath<ClassDiagramConfiguration, [String: Bool]>,
        default defaultKeyPath: KeyPath<ClassDiagramConfiguration, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.configuration[keyPath: overrideKeyPath][typeID]
                    ?? viewModel.configuration[keyPath: defaultKeyPath]
            },
            set: { newValue in
                mutate { $0[keyPath: overrideKeyPath][typeID] = newValue }
            }
        )
    }
}

extension ClassDiagramConfiguration {
    func widened(undoing reason: DiagramEmptyReason) -> ClassDiagramConfiguration {
        var widened = self
        switch reason {
        case .scope:
            widened.focus = nil
        case .filter:
            widened.filter = nil
            widened.minimumAccessLevel = nil
        case .scopeAndFilter:
            widened = self.widened(undoing: .scope).widened(undoing: .filter)
        case .codebase:
            break
        }
        return widened
    }
}
