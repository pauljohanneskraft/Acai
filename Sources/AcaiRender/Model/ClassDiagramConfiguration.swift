import Foundation
import AcaiCore
import AcaiQuality

/// Rendering configuration for a generated class diagram. Shared by the macOS app (persisted
/// inside `GeneratedDiagram`) and the CLI image command, so both produce identical diagrams
/// from the same options.
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
    /// Per-type overrides for property visibility, keyed by `TypeDeclaration.id`: effective
    /// visibility is `propertyVisibility[id] ?? showProperties`. Flipping the global toggle
    /// clears this map. App-only; the CLI leaves it empty.
    public var propertyVisibility: [String: Bool] = [:]
    public var methodVisibility: [String: Bool] = [:]
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
    public var minimumAccessLevel: AccessLevel?
    /// When `true`, hides types the source language marks as machine-generated (via its
    /// `LanguageConfiguration.generatedCodeFilter` — e.g. Dart's `*.freezed.dart`/`*.g.dart`).
    /// Has no effect for languages without a generated-code filter.
    public var hideGeneratedTypes: Bool = true
    /// When set, restricts the diagram to a single type and the slice of the
    /// relationship graph around it. `nil` renders the whole codebase.
    public var focus: FocusConfiguration?
    /// When set, only types this selector matches are shown — the same matching vocabulary
    /// `AcaiQuality`'s rules use, reused instead of a second, diagram-specific filter. `nil` shows
    /// every type.
    public var filter: AcaiQuality.Selector?

    public init() {}
}

extension ClassDiagramConfiguration {
    /// `true` if every one of `ids` currently shows both its properties and methods (per-type
    /// override, falling back to the global default) — the direction a bulk "toggle visibility"
    /// action should flip away from.
    public func showsMembers(forTypeIDs ids: some Collection<String>) -> Bool {
        ids.allSatisfy { id in
            (propertyVisibility[id] ?? showProperties) && (methodVisibility[id] ?? showMethods)
        }
    }

    public mutating func setMemberVisibility(_ show: Bool, forTypeIDs ids: some Collection<String>) {
        for id in ids {
            propertyVisibility[id] = show
            methodVisibility[id] = show
        }
    }
}
