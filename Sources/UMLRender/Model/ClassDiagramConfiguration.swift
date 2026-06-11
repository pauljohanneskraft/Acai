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

    public init() {}
}
