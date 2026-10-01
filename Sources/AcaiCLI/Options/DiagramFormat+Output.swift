import Foundation
import AcaiDiagram

extension DiagramFormat {
    init(inferredFromOutput path: String?) {
        switch path.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }) {
        case "dot", "gv":
            self = .dot
        case "mmd", "md", "mermaid":
            self = .mermaid
        default:
            self = .standard
        }
    }
}
