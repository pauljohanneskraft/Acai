import Foundation
import AcaiCore
import AcaiGit

extension ProjectCodebaseEditor {
    func reindex(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        do {
            _ = try await reindexOutcome(codebaseID: codebaseID)
        } catch {
            // An app-managed directory must never be re-pointed at a folder of the user's choosing.
            let relocatable = error is ScopedResourceAccess.Failure && codebase.managedCheckout == nil
            store.report(
                .app("Error.ProjectBrowserViewModel.ReindexFailed \(error.localizedDescription)"),
                relocating: relocatable ? codebaseID : nil)
        }
    }

    enum ReindexOutcome: Equatable {
        case completed
        case cancelled
    }

    enum ReindexFailure: LocalizedError {
        case codebaseNotFound

        var errorDescription: String? {
            String(localized: .app("Error.ReindexFailure.CodebaseNotFound"))
        }
    }

    /// Reindexes without reporting, for a caller that surfaces the failure itself.
    ///
    /// Parses the codebase's working tree or, for a local folder pinned to a revision, that
    /// revision's tree read from the repository's history into a temporary directory — the folder
    /// itself, its index and its HEAD are never written to.
    func reindexOutcome(codebaseID: UUID) async throws -> ReindexOutcome {
        guard let codebase = codebase(for: codebaseID) else { throw ReindexFailure.codebaseNotFound }
        let wasFirstIndex = !codebase.hasArtifact
        let path = codebase.directoryPath
        let bookmark = codebase.securityScopedBookmark
        let fileFilter = codebase.fileFilter
        let revision = codebase.pinnedRevision
        let analyzer = CodebaseAnalyzingResolver().resolve(codebaseID: codebaseID)
        let store = store
        // `Task.detached` doesn't inherit cancellation, so the parse is cancelled explicitly when
        // the wrapping `run` task is; `AnalysisService` and `GitDiffSnapshot` both observe it.
        // The artifact is saved inside the closure so the row's spinner outlasts the write.
        let reindexResult = try await store.activityCenter.run(
            title: .app("Activity.Indexing \(codebase.name)"),
            kind: .reindex, subject: .codebase(codebaseID)
        ) {
            let detached = Task.detached(priority: .userInitiated) {
                var refreshed: ScopedResourceAccess.Refreshed?
                let access = ScopedResourceAccess(path: path, bookmark: bookmark)
                let (artifact, fingerprint) = try await access.withResolvedURL(
                    onRefresh: { refreshed = $0 },
                    { url in
                        try await CodebaseIndexing(directory: url, revision: revision)
                            .run(analyzer: analyzer, fileFilter: fileFilter)
                    }
                )
                return (artifact, fingerprint, refreshed)
            }
            let (artifact, fingerprint, refreshed) = try await withTaskCancellationHandler {
                try await detached.value
            } onCancel: {
                detached.cancel()
            }
            try await store.saveArtifactAndWait(artifact, for: codebaseID)
            return (artifact, fingerprint, refreshed)
        }
        guard let (newArtifact, fingerprint, refreshed) = reindexResult else { return .cancelled }
        applyReindexResult(
            codebaseID: codebaseID, artifact: newArtifact, fingerprint: fingerprint, refreshed: refreshed,
            wasFirstIndex: wasFirstIndex)
        return .completed
    }

    /// Analyses a local folder at `revision` instead of its working tree (`nil` clears the pin),
    /// then reindexes. The checkout is never touched either way.
    func setAnalysedRevision(_ revision: String?, codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID), codebase.managedCheckout == nil,
              codebase.analysedRevision != revision
        else { return }
        mutateCodebase(codebaseID) { $0.analysedRevision = revision }
        invalidateAnalysis(codebaseID)
        await reindex(codebaseID: codebaseID)
    }

    /// Re-resolves indices after the suspension above — the user may have mutated the
    /// project/codebase list during the analysis — then applies the result to the stored codebase.
    private func applyReindexResult(
        codebaseID: UUID, artifact: CodeArtifact, fingerprint: CodeStateFingerprint?,
        refreshed: ScopedResourceAccess.Refreshed?, wasFirstIndex: Bool
    ) {
        guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
              let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID })
        else { return }
        store.projects[pIndex].codebases[cIndex].hasArtifact = true
        store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
        store.projects[pIndex].codebases[cIndex].indexedFingerprint = fingerprint
        store.projects[pIndex].codebases[cIndex].hasParseErrors = artifact.metadata.hasParseErrors
        store.projects[pIndex].codebases[cIndex].parseDiagnosticCount = artifact.metadata.parseDiagnostics.count
        if wasFirstIndex, store.projects[pIndex].codebases[cIndex].guidedRoute == nil {
            store.projects[pIndex].codebases[cIndex].guidedRoute = .offered
        }
        // A bookmark follows a folder that was moved or renamed, so the stored path has to
        // move with it — it's what the UI shows and what the file watcher opens.
        if let refreshed {
            store.projects[pIndex].codebases[cIndex].securityScopedBookmark = refreshed.bookmark
            store.projects[pIndex].codebases[cIndex].directoryPath = refreshed.url.path
        }
        persistProject(store.projects[pIndex].id)
    }
}

/// One indexing pass over an already-resolved directory. Does file I/O — call off the main actor.
struct CodebaseIndexing {
    let directory: URL
    let revision: String?

    func run(
        analyzer: CodebaseAnalyzing, fileFilter: FileFilter?
    ) async throws -> (CodeArtifact, CodeStateFingerprint) {
        let freshness = CodebaseFreshnessChecker(directoryPath: directory.path, revision: revision)
        guard let revision else {
            let artifact = try await analyzer.enrichedArtifact(at: directory, fileFilter: fileFilter)
            return (artifact, freshness.currentFingerprint())
        }
        let snapshot = GitDiffSnapshot(directory: directory, reference: revision)
        let fingerprint = freshness.currentFingerprint()
        let extracted = try snapshot.extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }
        return (try await analyzer.enrichedArtifact(at: extracted, fileFilter: fileFilter), fingerprint)
    }
}
