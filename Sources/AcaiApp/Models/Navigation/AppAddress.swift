import Foundation

/// A stable, shareable address of a project, codebase or diagram: `acai://<kind>/<uuid>`.
/// A diagram address covers generated and freeform diagrams alike — their ids never collide.
enum AppAddress: Hashable, Codable, Sendable {
    case project(UUID)
    case codebase(UUID)
    case diagram(UUID)

    static let scheme = "acai"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host(percentEncoded: false)?.lowercased(),
              url.query == nil, url.fragment == nil
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let id = UUID(uuidString: components[0]) else { return nil }
        switch host {
        case "project":
            self = .project(id)
        case "codebase":
            self = .codebase(id)
        case "diagram":
            self = .diagram(id)
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = kind
        components.path = "/" + id.uuidString
        guard let url = components.url else { preconditionFailure("An AppAddress always forms a valid URL") }
        return url
    }

    var id: UUID {
        switch self {
        case .project(let id), .codebase(let id), .diagram(let id):
            id
        }
    }

    private var kind: String {
        switch self {
        case .project:
            "project"
        case .codebase:
            "codebase"
        case .diagram:
            "diagram"
        }
    }
}
