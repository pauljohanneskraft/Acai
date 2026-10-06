import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
extension Notification.Name {
    /// Posted by the macOS memory-pressure source, which has no system notification of its own.
    static let memoryPressure = Notification.Name("AcaiMemoryPressure")
}
#endif

extension ProjectBrowserViewModel {
    func observeMemoryPressure() {
        #if os(macOS)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        // The handler is `@Sendable`, so it posts rather than reaching back into the view model.
        source.setEventHandler { NotificationCenter.default.post(name: .memoryPressure, object: nil) }
        source.activate()
        storeSubscriptions.insert(AnyCancellable { source.cancel() })
        let pressure = NotificationCenter.default.publisher(for: .memoryPressure)
        #else
        let pressure = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        #endif
        pressure
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.purgeCachesUnderMemoryPressure() }
            }
            .store(in: &storeSubscriptions)
    }

    /// Keeps only what the current selection renders from; the rest reloads or re-derives on next access.
    func purgeCachesUnderMemoryPressure() {
        purgeComparisonCaches()
        purgeAnalysesNotOnScreen()
        let displayedCodebases = displayedCodebaseIDs
        displayArtifactCache = displayArtifactCache.filter { displayedCodebases.contains($0.key) }
    }

    var displayedCodebaseIDs: Set<UUID> {
        switch selection {
        case .codebase(let id), .query(let id):
            return [id]
        case .generatedDiagram(let id):
            return Set(generatedDiagram(for: id).map { [$0.codebaseID] } ?? [])
        case .project(let id), .findings(let id):
            return Set(store.projects.first { $0.id == id }?.codebases.map(\.id) ?? [])
        case .freeformDiagram, .repository, .none:
            return []
        }
    }
}
