import Foundation
import UMLCore
import UMLRender

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
    /// The diagram's rendering configuration. The type itself lives in `UMLRender`
    /// (shared with the CLI image renderer); this alias keeps the historical
    /// `GeneratedDiagram.Configuration` spelling used throughout the app.
    typealias Configuration = DiagramConfiguration
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
