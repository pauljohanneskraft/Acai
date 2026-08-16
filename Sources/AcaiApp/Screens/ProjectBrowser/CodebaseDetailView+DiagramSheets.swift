import SwiftUI

extension CodebaseDetailView {

    @ViewBuilder
    func stateConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            StateConfigSheet(
                artifact: artifact,
                onCancel: { stateConfigContext = nil },
                onCreate: { config in
                    let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .stateDiagram(config)
                    )
                    stateConfigContext = nil
                    // Deferred: selecting in the same synchronous closure as this sheet's own
                    // dismissal (a separate window on macOS) has been observed to occasionally drop
                    // the parent NavigationSplitView's detail-column update entirely.
                    if let id {
                        Task { @MainActor in model.selection = .generatedDiagram(id) }
                    }
                }
            )
        }
    }

    @ViewBuilder
    func callGraphConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            CallGraphConfigSheet(
                artifact: artifact,
                onCancel: { callGraphConfigContext = nil },
                onCreate: { scope in
                    let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .callGraph(scope)
                    )
                    callGraphConfigContext = nil
                    // Deferred — see `stateConfigSheet`'s `onCreate`.
                    if let id {
                        Task { @MainActor in model.selection = .generatedDiagram(id) }
                    }
                }
            )
        }
    }

    @ViewBuilder
    func sequenceConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            SequenceConfigSheet(
                artifact: artifact,
                onCancel: { sequenceConfigContext = nil },
                onCreate: { config in
                    let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .sequenceDiagram(config)
                    )
                    sequenceConfigContext = nil
                    // Deferred — see `stateConfigSheet`'s `onCreate`.
                    if let id {
                        Task { @MainActor in model.selection = .generatedDiagram(id) }
                    }
                }
            )
        }
    }
}
