import Foundation
import AcaiCore
import AcaiDiagram

extension TypeKind {
    var title: LocalizedStringResource {
        switch self {
        case .class:
            .app("TypeKind.Class")
        case .actor:
            .app("TypeKind.Actor")
        case .struct:
            .app("TypeKind.Struct")
        case .enum:
            .app("TypeKind.Enum")
        case .protocol:
            .app("TypeKind.Protocol")
        case .interface:
            .app("TypeKind.Interface")
        case .trait:
            .app("TypeKind.Trait")
        case .typeAlias:
            .app("TypeKind.TypeAlias")
        case .object:
            .app("TypeKind.Object")
        case .extension:
            .app("TypeKind.Extension")
        case .annotation:
            .app("TypeKind.Annotation")
        case .module:
            .app("TypeKind.Module")
        case .record:
            .app("TypeKind.Record")
        case .mixin:
            .app("TypeKind.Mixin")
        }
    }
}

extension StateDiagram.State.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .initial:
            .app("StateKind.Initial")
        case .normal:
            .app("StateKind.Normal")
        case .final:
            .app("StateKind.Final")
        case .choice:
            .app("StateKind.Choice")
        case .fork:
            .app("StateKind.Fork")
        case .join:
            .app("StateKind.Join")
        case .composite:
            .app("StateKind.Composite")
        }
    }
}

extension SequenceDiagram.Participant.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .actor:
            .app("ParticipantKind.Actor")
        case .object:
            .app("ParticipantKind.Object")
        case .boundary:
            .app("ParticipantKind.Boundary")
        case .control:
            .app("ParticipantKind.Control")
        case .entity:
            .app("ParticipantKind.Entity")
        case .database:
            .app("ParticipantKind.Database")
        }
    }
}

extension FreeformDiagram.Node.Content {
    var title: LocalizedStringResource {
        switch self {
        case .type(let type):
            type.typeKind.title
        case .state(let kind):
            kind.title
        case .lifeline(let kind):
            kind.title
        case .method:
            .app("DiagramElementDescription.Method")
        case .note:
            .app("FreeformKind.Note")
        case .actor:
            .app("FreeformKind.Actor")
        case .useCase:
            .app("FreeformKind.UseCase")
        case .boundary:
            .app("FreeformKind.Boundary")
        case .component:
            .app("FreeformKind.Component")
        case .package:
            .app("FreeformKind.Package")
        case .deploymentNode:
            .app("FreeformKind.DeploymentNode")
        case .database:
            .app("FreeformKind.Database")
        case .artifact:
            .app("FreeformKind.Artifact")
        case .subsystem:
            .app("FreeformKind.Subsystem")
        case .entity:
            .app("FreeformKind.Entity")
        case .fragment:
            .app("FreeformKind.Fragment")
        }
    }
}

extension Relationship.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .inheritance:
            .app("RelationshipKind.Inheritance")
        case .conformance:
            .app("RelationshipKind.Conformance")
        case .composition:
            .app("RelationshipKind.Composition")
        case .aggregation:
            .app("RelationshipKind.Aggregation")
        case .association:
            .app("RelationshipKind.Association")
        case .dependency:
            .app("RelationshipKind.Dependency")
        case .extension:
            .app("RelationshipKind.Extension")
        case .nesting:
            .app("RelationshipKind.Nesting")
        }
    }
}
