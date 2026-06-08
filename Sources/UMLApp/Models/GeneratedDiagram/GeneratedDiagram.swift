import Foundation
import UMLCore

struct GeneratedDiagram: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var type: DiagramType
    var codebaseID: UUID
    var configuration: Configuration
    var nodePositions: [String: NodePosition] = [:]
    /// User-overridden node sizes (from resize handles).
    var nodeSizes: [String: NodeSize] = [:]
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var createdDate: Date = Date()
    var lastModified: Date = Date()
}

extension GeneratedDiagram {
    struct Configuration: Codable, Hashable, Sendable {
        /// How diagram nodes are partitioned for layout. `.product` additionally draws a
        /// labelled "package" box behind each compiled product (build target / module).
        enum Grouping: String, Codable, Hashable, Sendable, CaseIterable {
            case none
            case directory
            case product
        }

        var showProperties: Bool = true
        var showMethods: Bool = true
        var showEnumCases: Bool = true
        var showRelationships: Bool = true
        var showInheritance: Bool = true
        var showComposition: Bool = true
        var showDependency: Bool = true
        var grouping: Grouping = .product
        var showExternalTypes: Bool = false
        /// Access level filter — only show members at or above this level.
        var minimumAccessLevel: AccessLevel?
        /// When `true`, hides types originating from Dart generated files
        /// (e.g. `*.freezed.dart`, `*.g.dart`) as well as types whose names
        /// match common code-generation patterns.
        var hideGeneratedDartTypes: Bool = true

        init() {}

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

        init(from decoder: any Decoder) throws {
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
}

extension GeneratedDiagram {
    struct NodePosition: Codable, Hashable, Sendable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }

        var cgPoint: CGPoint {
            CGPoint(x: x, y: y)
        }
    }
}

extension GeneratedDiagram {
    struct NodeSize: Codable, Hashable, Sendable {
        var width: Double
        var height: Double

        init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        init(size: CGSize) {
            self.width = Double(size.width)
            self.height = Double(size.height)
        }

        var cgSize: CGSize {
            CGSize(width: width, height: height)
        }
    }
}
