import Foundation

extension ProjectBrowserView {
    func resolveHandoffContinuation(_ target: HandoffContinuationPresenter.Target?) {
        guard let target else { return }
        defer { handoffPresenter.pendingTarget = nil }
        switch target {
        case .diagram(let id):
            model.selection = .generatedDiagram(id)
        case .codebase(let id):
            model.selection = .codebase(id)
        case .spotlightItem(let identifier):
            Task { await resolveSpotlightTap(identifier: identifier) }
        }
    }

    private func resolveSpotlightTap(identifier: String) async {
        let builder = QuickOpenIndexBuilder(
            projects: model.store.projects, artifacts: model.store.artifacts,
            generatedDiagrams: model.store.generatedDiagrams, freeformDiagrams: model.store.freeformDiagrams
        )
        guard let entry = await Task.detached(priority: .userInitiated, operation: {
            builder.entries().first { $0.id == identifier }
        }).value else { return }
        model.applyQuickOpenEntryDefault(entry)
    }
}
