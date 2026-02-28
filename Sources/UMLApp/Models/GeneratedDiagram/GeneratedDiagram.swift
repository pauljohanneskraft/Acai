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
        var showProperties: Bool = true
        var showMethods: Bool = true
        var showEnumCases: Bool = true
        var showRelationships: Bool = true
        var showInheritance: Bool = true
        var showComposition: Bool = true
        var showDependency: Bool = true
        var groupByDirectory: Bool = true
        var showExternalTypes: Bool = false
        /// Access level filter — only show members at or above this level.
        var minimumAccessLevel: AccessLevel?
        /// When `true`, hides types originating from Dart generated files
        /// (e.g. `*.freezed.dart`, `*.g.dart`) as well as types whose names
        /// match common code-generation patterns.
        var hideGeneratedDartTypes: Bool = true
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
