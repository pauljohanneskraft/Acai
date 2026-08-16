import Foundation
import AcaiCore

enum CodeElementReference: Hashable, Sendable {
    case type(id: String)
    /// Identified by simple names, since no stable per-method id exists in the data model.
    case method(typeName: String?, methodName: String)
    case module(name: String)
    case relationship(source: String, target: String, kind: Relationship.Kind)
}

struct CodeElementResolution: Identifiable, Hashable {
    var diagramType: DiagramType
    var target: Target

    var id: DiagramType { diagramType }

    enum Target: Hashable {
        case existing(UUID)
        /// Offer to create one pre-scoped like this, never a blank configuration sheet.
        case create(GeneratedDiagram.Content)
    }
}
