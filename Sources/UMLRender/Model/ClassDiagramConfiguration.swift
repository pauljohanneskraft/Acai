import Foundation
import UMLCore

/// Rendering configuration for a generated class diagram: which members and relationships
/// to show, how to group nodes, and access-level / generated-code filtering.
///
/// Shared by the macOS app (where it is persisted inside `GeneratedDiagram`) and the CLI
/// image command, so both produce identical diagrams from the same options.
public struct ClassDiagramConfiguration: Codable, Hashable, Sendable {
    /// How diagram nodes are partitioned for layout. `.product` additionally draws a
    /// labelled "package" box behind each compiled product (build target / module).
    public enum Grouping: String, Codable, Hashable, Sendable, CaseIterable {
        case none
        case directory
        case product
    }

    public var showProperties: Bool = true
    public var showMethods: Bool = true
    public var showEnumCases: Bool = true
    /// Per-type overrides for property visibility, keyed by `TypeDeclaration.id`. A type's
    /// effective visibility is `propertyVisibility[id] ?? showProperties`, so a type can be
    /// shown or hidden independently of the global default. Flipping the global toggle clears
    /// this map, resetting every type to the new default. App-only; the CLI leaves it empty.
    public var propertyVisibility: [String: Bool] = [:]
    /// Per-type overrides for method visibility. See `propertyVisibility`.
    public var methodVisibility: [String: Bool] = [:]
    /// Per-type overrides for enum-case visibility. See `propertyVisibility`.
    public var enumCaseVisibility: [String: Bool] = [:]
    public var showRelationships: Bool = true
    public var showInheritance: Bool = true
    public var showComposition: Bool = true
    public var showDependency: Bool = true
    /// When `true`, association/aggregation/composition edges show their `*` / `0..1` / `1`
    /// multiplicity labels near the edge endpoints.
    public var showMultiplicities: Bool = true
    /// When `true`, stereotypes derived from real type annotations (e.g. `@Entity`→`«entity»`)
    /// are shown in node headers in addition to the kind-based stereotype.
    public var showAnnotationStereotypes: Bool = true
    public var grouping: Grouping = .product
    public var showExternalTypes: Bool = false
    /// Access level filter — only show members at or above this level.
    public var minimumAccessLevel: AccessLevel?
    /// When `true`, hides types the source language marks as machine-generated (via its
    /// `LanguageConfiguration.generatedCodeFilter` — e.g. Dart's `*.freezed.dart`/`*.g.dart`).
    /// Has no effect for languages without a generated-code filter.
    public var hideGeneratedTypes: Bool = true
    /// When set, restricts the diagram to a single type and the slice of the
    /// relationship graph around it. `nil` renders the whole codebase.
    public var focus: FocusConfiguration?

    public init() {}
}
