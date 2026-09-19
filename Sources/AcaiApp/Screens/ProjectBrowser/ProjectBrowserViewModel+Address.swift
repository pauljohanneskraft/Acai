import Foundation

extension ProjectBrowserViewModel {
    enum AddressFailure: LocalizedError, Equatable {
        case malformed(URL)
        case projectNotFound
        case codebaseNotFound
        case diagramNotFound

        var errorDescription: String? {
            switch self {
            case .malformed(let url):
                String(localized: .app("Error.AppAddress.Malformed \(url.absoluteString)"))
            case .projectNotFound:
                String(localized: .app("Error.AppAddress.ProjectNotFound"))
            case .codebaseNotFound:
                String(localized: .app("Error.AppAddress.CodebaseNotFound"))
            case .diagramNotFound:
                String(localized: .app("Error.AppAddress.DiagramNotFound"))
            }
        }
    }

    func selection(for address: AppAddress) throws(AddressFailure) -> Selection {
        switch address {
        case .project(let id):
            guard store.projects.contains(where: { $0.id == id }) else { throw .projectNotFound }
            return .project(id)
        case .codebase(let id):
            guard codebase(for: id) != nil else { throw .codebaseNotFound }
            return .codebase(id)
        case .diagram(let id):
            if store.generatedDiagrams[id] != nil { return .generatedDiagram(id) }
            if store.freeformDiagrams[id] != nil { return .freeformDiagram(id) }
            throw .diagramNotFound
        }
    }

    /// `nil` after reporting why `url` can't be opened, so a bad link never lands anywhere arbitrary.
    func resolve(url: URL) -> Selection? {
        do throws(AddressFailure) {
            guard let address = AppAddress(url: url) else { throw .malformed(url) }
            return try selection(for: address)
        } catch {
            store.report(error.errorDescription ?? "")
            return nil
        }
    }
}

extension ProjectBrowserViewModel.Selection {
    /// `nil` for a repository, which is identified by its remote rather than by anything the app owns.
    var address: AppAddress? {
        switch self {
        case .project(let id), .findings(let id):
            .project(id)
        case .codebase(let id), .query(let id):
            .codebase(id)
        case .generatedDiagram(let id), .freeformDiagram(let id):
            .diagram(id)
        case .repository:
            nil
        }
    }

    var diagramID: UUID? {
        switch self {
        case .generatedDiagram(let id), .freeformDiagram(let id):
            id
        default:
            nil
        }
    }
}
