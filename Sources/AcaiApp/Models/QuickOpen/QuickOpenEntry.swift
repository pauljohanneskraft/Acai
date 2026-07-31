import Foundation
import AcaiCore

/// One searchable thing Quick Open can find and jump to: a type, method, module, or existing
/// diagram, from any project. Carries enough to both display a result row and resolve it — either
/// directly (a diagram opens by selecting it) or through `CodeElementReference`'s existing
/// resolution mechanism (a type/method/module opens via the same "Open in…" machinery every other
/// surface in the app uses — Quick Open reuses it rather than inventing a second way to turn "a
/// type" into "a diagram").
struct QuickOpenEntry: Identifiable, Hashable {
    enum Kind: Hashable {
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
