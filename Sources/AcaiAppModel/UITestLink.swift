import Foundation

/// A link only a UI test sends, reaching screens no user-facing `acai://` address names: a
/// project's findings, a codebase's query, a repository, or a presented sheet. Written as
/// `acai://uitest/<route>`, so it needs no URL scheme of its own.
public enum UITestLink: Equatable, Sendable {
    case findings(projectID: UUID)
    case query(codebaseID: UUID)
    case repository(remoteURL: URL)
    case present(Presentation)

    public enum Presentation: Equatable, Sendable {
        case settings
        case keyboardShortcuts
        case quickOpen
        case newProject
        case newCodebase(projectID: UUID)
        case deleteProject(UUID)
        case deleteCodebase(UUID)
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "acai", url.host(percentEncoded: false)?.lowercased() == "uitest"
        else { return nil }
        let route = url.pathComponents.filter { $0 != "/" }
        switch route.first {
        case "findings":
            guard let id = route.uuid(at: 1), route.count == 2 else { return nil }
            self = .findings(projectID: id)
        case "query":
            guard let id = route.uuid(at: 1), route.count == 2 else { return nil }
            self = .query(codebaseID: id)
        case "repository":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard route.count == 1, let remote = query?.first(where: { $0.name == "url" })?.value,
                  let remoteURL = URL(string: remote)
            else { return nil }
            self = .repository(remoteURL: remoteURL)
        case "present":
            guard let presentation = Presentation(route: Array(route.dropFirst())) else { return nil }
            self = .present(presentation)
        default:
            return nil
        }
    }
}

extension UITestLink.Presentation {
    private static let fixed: [String: Self] = [
        "settings": .settings,
        "keyboard-shortcuts": .keyboardShortcuts,
        "quick-open": .quickOpen,
        "new-project": .newProject
    ]

    private static let identified: [String: @Sendable (UUID) -> Self] = [
        "new-codebase": { .newCodebase(projectID: $0) },
        "delete-project": { .deleteProject($0) },
        "delete-codebase": { .deleteCodebase($0) }
    ]

    init?(route: [String]) {
        guard let name = route.first else { return nil }
        if route.count == 1, let presentation = Self.fixed[name] {
            self = presentation
        } else if route.count == 2, let make = Self.identified[name], let id = route.uuid(at: 1) {
            self = make(id)
        } else {
            return nil
        }
    }
}

private extension Array where Element == String {
    func uuid(at index: Int) -> UUID? {
        indices.contains(index) ? UUID(uuidString: self[index]) : nil
    }
}
