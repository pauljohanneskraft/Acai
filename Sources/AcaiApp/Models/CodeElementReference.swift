import Foundation
import AcaiCore

/// A lightweight pointer to one code element — a type, method, module, or relationship — that any
/// surface already holding a `TypeDeclaration`/`Relationship`/`Violation`/diagram node has enough
/// information to construct. See `USABILITY_IMPROVEMENTS.md` Part 2, "The fix: one shared
/// `CodeElementReference`."
///
/// This type carries identity only; `resolutions(in:existingDiagrams:)` (in
/// `CodeElementReference+Resolution.swift`) is its one capability — resolving into every diagram
/// type that can meaningfully show it.
enum CodeElementReference: Hashable, Sendable {
    /// A type (class/struct/enum/protocol/…), identified by its stable `TypeDeclaration.id`.
    case type(id: String)
    /// A method (or free function, when `typeName` is `nil`), identified by simple names — the
    /// same way `SequenceDiagramConfiguration`/`CallGraphScope.type` already do, since no stable
    /// per-method id exists in the data model.
    case method(typeName: String?, methodName: String)
    /// A build module/product, identified by `ModuleResolver`'s product name.
    case module(name: String)
    /// A relationship between two types, identified by their ids.
    case relationship(source: String, target: String, kind: Relationship.Kind)
}

/// One diagram type a `CodeElementReference` can resolve into, and where that resolution lands.
struct CodeElementResolution: Identifiable, Hashable {
    var diagramType: DiagramType
    var target: Target

    var id: DiagramType { diagramType }

    enum Target: Hashable {
        /// An already-open diagram that already shows this element — jump to it.
        case existing(UUID)
        /// No existing diagram shows it — offer to create one pre-scoped like this, never a blank
        /// configuration sheet.
        case create(GeneratedDiagram.Content)
    }
}
