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
    public var grouping: Grouping = .product
    public var showExternalTypes: Bool = false
    /// Access level filter — only show members at or above this level.
    public var minimumAccessLevel: AccessLevel?
    /// When `true`, hides types originating from Dart generated files
    /// (e.g. `*.freezed.dart`, `*.g.dart`) as well as types whose names
    /// match common code-generation patterns.
    public var hideGeneratedDartTypes: Bool = true
    /// When set, restricts the diagram to a single type and the slice of the
    /// relationship graph around it. `nil` renders the whole codebase.
    public var focus: FocusConfiguration?

    public init() {}

    /// Decodes a configuration tolerantly: any key absent from the JSON falls back to the
    /// property's default. Swift's synthesized `Decodable` throws `keyNotFound` for missing
    /// keys instead of using defaults, which would make diagrams saved before a field was
    /// added fail to load (and `ProjectStore` silently drops diagrams that fail to decode).
    /// A hand-written decoder keeps older saved diagrams loadable as new options are added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func bool(_ key: CodingKeys, default fallback: Bool) throws -> Bool {
            try container.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }
        showProperties = try bool(.showProperties, default: true)
        showMethods = try bool(.showMethods, default: true)
        showEnumCases = try bool(.showEnumCases, default: true)
        propertyVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .propertyVisibility) ?? [:]
        methodVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .methodVisibility) ?? [:]
        enumCaseVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .enumCaseVisibility) ?? [:]
        showRelationships = try bool(.showRelationships, default: true)
        showInheritance = try bool(.showInheritance, default: true)
        showComposition = try bool(.showComposition, default: true)
        showDependency = try bool(.showDependency, default: true)
        grouping = try container.decodeIfPresent(Grouping.self, forKey: .grouping) ?? .product
        showExternalTypes = try bool(.showExternalTypes, default: false)
        minimumAccessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .minimumAccessLevel)
        hideGeneratedDartTypes = try bool(.hideGeneratedDartTypes, default: true)
        focus = try container.decodeIfPresent(FocusConfiguration.self, forKey: .focus)
    }
}
