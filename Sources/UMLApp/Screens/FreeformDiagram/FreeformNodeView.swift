import SwiftUI
import UMLDiagram
import UMLRender

struct FreeformNodeView: View {
    let node: FreeformDiagram.Node
    let isSelected: Bool
    /// Explicit size for resizable container nodes. `nil` for auto-sized nodes.
    var size: CGSize?

    var body: some View {
        switch node.content {
        case .type(let content):
            TypeNodeView(node: node, content: content, isSelected: isSelected)
        case .note(let text):
            NoteNodeView(name: node.name, text: text, isSelected: isSelected)
        case .actor:
            LabelNodeView.actor(name: node.name, isSelected: isSelected)
        case .useCase:
            UseCaseNodeView(name: node.name, isSelected: isSelected)
        case .package:
            ContainerNodeView(
                name: node.name, stereotype: "package",
                style: .package, isSelected: isSelected, size: size
            )
        case .boundary:
            ContainerNodeView(
                name: node.name, stereotype: "boundary",
                style: .boundary, isSelected: isSelected, size: size
            )
        case .subsystem:
            ContainerNodeView(
                name: node.name, stereotype: "subsystem",
                style: .subsystem, isSelected: isSelected, size: size
            )
        case .database:
            LabelNodeView.database(name: node.name, isSelected: isSelected)
        case .lifeline(let kind):
            ParticipantHeaderView(name: node.name, kind: kind, isSelected: isSelected)
        case .state(let kind):
            // Shared with the generated state view for visual parity. The explicit frame
            // (states size by kind + title) stops the flexible state box from greedily
            // expanding under `.measuredNode`.
            let size = StateLayoutModel.estimatedSize(
                for: .init(id: node.id, name: node.name, kind: kind)
            )
            StateNodeView(name: node.name, kind: kind, isSelected: isSelected)
                .frame(width: size.width, height: size.height)
        case .method:
            MethodNodeView(name: node.name, isSelected: isSelected)
        default:
            // component, deploymentNode, artifact, entity
            StereotypedBoxNodeView(
                name: node.name,
                stereotype: node.content.stereotype,
                systemImage: node.content.kind.systemImage,
                isSelected: isSelected
            )
        }
    }
}
