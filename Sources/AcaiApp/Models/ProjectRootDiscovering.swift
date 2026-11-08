import AcaiCore
import AcaiLibrary
import Foundation

/// Synchronous: the caller moves it off the main actor and holds the folder's scope open around it.
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
