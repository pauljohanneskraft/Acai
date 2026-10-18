import AcaiCore
import AcaiLibrary
import Foundation

/// Finds the project roots inside a folder, so adding a codebase can offer one per root instead of
/// indexing a parent folder as a single undifferentiated codebase. Synchronous by design: the caller
/// owns getting it off the main actor and holding the folder's security scope open around it, the
/// same way every other filesystem read here does.
protocol ProjectRootDiscovering: Sendable {
    func discoverRoots(in directory: URL) -> [CodeArtifact.DiscoveredRoot]
}

struct ProjectRootDiscoverer: ProjectRootDiscovering {
    private let discovery: ProjectDiscovery

    init(service: AnalysisService = .standard) {
        discovery = service.projectDiscovery
    }

    func discoverRoots(in directory: URL) -> [CodeArtifact.DiscoveredRoot] {
        discovery.discoverSourceSpecs(in: directory, requestedLanguages: [])
            .discoveredRoots(relativeTo: directory)
    }
}
