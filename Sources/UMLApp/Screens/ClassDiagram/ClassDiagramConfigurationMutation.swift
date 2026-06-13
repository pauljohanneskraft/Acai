import SwiftUI
import UMLCore
import UMLRender

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

    /// Read-modify-write the configuration, persisting and applying it live.
    func mutate(_ transform: (inout ClassDiagramConfiguration) -> Void) {
        var configuration = viewModel.configuration
        transform(&configuration)
        model.updateClassDiagramConfiguration(diagramID: diagramID, configuration: configuration)
        viewModel.applyConfiguration(configuration, artifact: artifact)
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

    /// A toggle binding for one type's per-category visibility. Reading falls back to the global
    /// default when the type has no override; writing records an explicit per-type override.
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
