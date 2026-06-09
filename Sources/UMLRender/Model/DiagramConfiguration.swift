import Foundation
import UMLCore

/// Rendering configuration for a generated class diagram: which members and relationships
/// to show, how to group nodes, and access-level / generated-code filtering.
///
/// Shared by the macOS app (where it is persisted inside `GeneratedDiagram`) and the CLI
/// image command, so both produce identical diagrams from the same options.
public struct DiagramConfiguration: Codable, Hashable, Sendable {
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

    // MARK: - Decode-tolerant Codable
    //
    // Saved diagrams predate several of these keys (synthesized `Codable` would
    // throw on a missing key), and the old `groupByDirectory` boolean has been
    // replaced by `grouping`. Decode every field leniently and migrate the legacy
    // flag. `encode(to:)` stays synthesized via `CodingKeys` (real properties only).
    enum CodingKeys: String, CodingKey {
        case showProperties, showMethods, showEnumCases, showRelationships
        case showInheritance, showComposition, showDependency
        case grouping, showExternalTypes, minimumAccessLevel, hideGeneratedDartTypes
    }

    private enum LegacyKeys: String, CodingKey {
        case groupByDirectory
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? container.decode(Bool.self, forKey: key)) ?? fallback
        }
        showProperties = flag(.showProperties, true)
        showMethods = flag(.showMethods, true)
        showEnumCases = flag(.showEnumCases, true)
        showRelationships = flag(.showRelationships, true)
        showInheritance = flag(.showInheritance, true)
        showComposition = flag(.showComposition, true)
        showDependency = flag(.showDependency, true)
        showExternalTypes = flag(.showExternalTypes, false)
        hideGeneratedDartTypes = flag(.hideGeneratedDartTypes, true)
        minimumAccessLevel = try? container.decode(AccessLevel.self, forKey: .minimumAccessLevel)
        grouping = decodeGrouping(from: decoder, container: container) ?? .product
    }

    /// Resolves the grouping mode, migrating the legacy `groupByDirectory` boolean.
    private func decodeGrouping(
        from decoder: any Decoder,
        container: KeyedDecodingContainer<CodingKeys>
    ) -> Grouping? {
        if let value = try? container.decode(Grouping.self, forKey: .grouping) {
            return value
        }
        if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let groupByDirectory = try? legacy.decode(Bool.self, forKey: .groupByDirectory) {
            return groupByDirectory ? Grouping.directory : Grouping.none
        }
        return nil
    }
}
