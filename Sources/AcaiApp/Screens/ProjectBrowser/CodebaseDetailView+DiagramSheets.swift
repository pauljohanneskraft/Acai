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
                    if let id {
                        model.open(.generatedDiagram(id))
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
                    if let id {
                        model.open(.generatedDiagram(id))
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
                    if let id {
                        model.open(.generatedDiagram(id))
                    }
                }
            )
        }
    }
}
