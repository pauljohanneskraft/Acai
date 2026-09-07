import Foundation
import AcaiCore

/// One searchable thing Quick Open can find and jump to: a project, codebase, type, method,
/// module, or existing diagram, from any project. Resolves either directly (a project/codebase/
/// diagram opens by selecting it) or through `CodeElementReference`'s resolution mechanism (a
/// type/method/module). Also the on-device Core Spotlight index's source of truth — see
/// `SpotlightIndexer`.
struct QuickOpenEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case project
        case codebase
        case type
        case method
        case module
        case generatedDiagram
        case freeformDiagram
    }

    /// Stable across a rebuild of the index for the same underlying element, so results don't
    /// visually thrash identity while the user is still typing.
    var id: String
    var name: String
    var kind: Kind
    /// A short secondary line — the codebase/project this result lives in, so two identically-named
    /// types in different codebases are distinguishable in the results list.
    var subtitle: String
    var projectID: UUID
    var codebaseID: UUID?
    /// Set for `.type`/`.method`/`.module` entries — resolved through the shared
    /// `CodeElementReference` mechanism. `nil` for diagram entries, which resolve directly via
    /// `generatedDiagramID`/`freeformDiagramID` instead.
    var reference: CodeElementReference?
    var generatedDiagramID: UUID?
    var freeformDiagramID: UUID?

    var systemImage: String {
        switch kind {
        case .project:
            "tray.full"
        case .codebase:
            "folder"
        case .type:
            "square.on.square"
        case .method:
            "function"
        case .module:
            "shippingbox"
        case .generatedDiagram:
            "rectangle.3.group"
        case .freeformDiagram:
            "square.on.square.dashed"
        }
    }
}
