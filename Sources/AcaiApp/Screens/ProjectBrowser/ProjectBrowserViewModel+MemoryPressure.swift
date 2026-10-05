import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
extension Notification.Name {
    /// macOS has no memory-warning notification, so the memory-pressure `DispatchSource` posts this
    /// one and both platforms purge through the same subscription.
    static let memoryPressure = Notification.Name("AcaiMemoryPressure")
}
#endif

extension ProjectBrowserViewModel {
    /// Subscribes to the system's memory-pressure signal for as long as this view model lives.
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

    /// Drops every cached snapshot, derivation and analysis the current selection isn't rendering
    /// from. What is on screen stays, so nothing the user is looking at degrades; anything dropped is
    /// re-loaded behind the compare panel's loading indicator, or re-derived, on next access.
    func purgeCachesUnderMemoryPressure() {
        purgeComparisonCaches()
        purgeAnalysesNotOnScreen()
        for evicted in displayArtifactRecency.purge(retaining: displayedCodebaseIDs) {
            displayArtifactCache.removeValue(forKey: evicted)
        }
    }

    /// The codebases the current selection renders from.
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
