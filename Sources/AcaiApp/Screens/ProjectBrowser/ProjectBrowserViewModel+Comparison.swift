import Foundation
import AcaiGit
import AcaiCore

extension ProjectBrowserViewModel {
    // MARK: - Delta comparison (git revision)

    /// `ref` is a branch/tag/SHA, or — for a pull-request comparison's "old" side — a resolved
    /// merge-base SHA.
    struct ComparisonKey: Hashable {
        let directory: String
        let ref: String
    }

    /// Identity of a resolved merge-base, so a pull-request comparison's read accessors don't
    /// re-run libgit2 merge-base resolution on every view update.
    struct MergeBaseKey: Hashable {
        let directory: String
        let base: String
        let head: String
    }

    /// Drops saved positions since the rendered element set changes, and exits pull-request mode.
    func updateComparisonGitRef(diagramID: UUID, ref: String?) {
        comparisonError = nil
        diagrams.mutate(diagramID, clearPositions: true) {
            $0.comparisonGitRef = (ref?.isEmpty == true) ? nil : ref
            $0.comparisonBaseRef = nil
        }
        resetComparisonReviewState(diagramID: diagramID)
    }

    /// Selects a pull request as the comparison: `head` (the PR's own commits) becomes the "new"
    /// side and `base` (the PR's target branch) is resolved to their merge-base for the "old" side
    /// — three-dot semantics, so a base branch that has moved on since the PR forked doesn't leak
    /// its own unrelated changes into the diff.
    func selectComparisonPullRequest(diagramID: UUID, base: String, head: String) {
        comparisonError = nil
        diagrams.mutate(diagramID, clearPositions: true) {
            $0.comparisonGitRef = head
            $0.comparisonBaseRef = base
        }
        resetComparisonReviewState(diagramID: diagramID)
    }

    private func resetComparisonReviewState(diagramID: UUID) {
        comparisonReviewedFiles[diagramID] = []
        comparisonReviewedFindings[diagramID] = []
    }

    func isComparisonFileReviewed(diagramID: UUID, filePath: String) -> Bool {
        comparisonReviewedFiles[diagramID, default: []].contains(filePath)
    }

    func toggleComparisonFileReviewed(diagramID: UUID, filePath: String) {
        var reviewed = comparisonReviewedFiles[diagramID, default: []]
        if !reviewed.insert(filePath).inserted { reviewed.remove(filePath) }
        comparisonReviewedFiles[diagramID] = reviewed
    }

    func isComparisonFindingReviewed(diagramID: UUID, findingID: String) -> Bool {
        comparisonReviewedFindings[diagramID, default: []].contains(findingID)
    }

    func toggleComparisonFindingReviewed(diagramID: UUID, findingID: String) {
        var reviewed = comparisonReviewedFindings[diagramID, default: []]
        if !reviewed.insert(findingID).inserted { reviewed.remove(findingID) }
        comparisonReviewedFindings[diagramID] = reviewed
    }

    /// With `comparisonBaseRef` unset (HEAD/ref/custom mode), loads just the "old" side, diffed
    /// against the live working tree. With it set (pull-request mode), first resolves the
    /// merge-base of `comparisonBaseRef` and `comparisonGitRef`, then loads both that merge-base and
    /// `comparisonGitRef` itself as historical snapshots — no live working tree is involved.
    func ensureComparisonLoaded(for diagram: GeneratedDiagram) async {
        guard let codebase = codebase(for: diagram.codebaseID),
              let ref = diagram.comparisonGitRef
        else { return }
        let directory = codebase.directoryPath
        let fileFilter = codebase.fileFilter
        let url = URL(fileURLWithPath: directory).standardizedFileURL

        guard let baseRef = diagram.comparisonBaseRef else {
            await loadComparisonSnapshot(directory: directory, url: url, ref: ref, fileFilter: fileFilter)
            return
        }

        let mergeBaseKey = MergeBaseKey(directory: directory, base: baseRef, head: ref)
        if resolvedMergeBases[mergeBaseKey] == nil {
            do {
                let sha = try await Task.detached(priority: .userInitiated) {
                    try GitCheckout(directory: url).mergeBase(baseRef, ref)
                }.value
                resolvedMergeBases[mergeBaseKey] = sha
            } catch {
                comparisonError = error.localizedDescription
                return
            }
        }
        guard let mergeBaseSHA = resolvedMergeBases[mergeBaseKey] else { return }
        await loadComparisonSnapshot(directory: directory, url: url, ref: mergeBaseSHA, fileFilter: fileFilter)
        await loadComparisonSnapshot(directory: directory, url: url, ref: ref, fileFilter: fileFilter)
    }

    private func loadComparisonSnapshot(directory: String, url: URL, ref: String, fileFilter: FileFilter?) async {
        let key = ComparisonKey(directory: directory, ref: ref)
        guard comparisonArtifacts[key] == nil else { return }
        do {
            let semantic = try await Task.detached(priority: .userInitiated) {
                try GitRevisionSnapshot(directory: url, reference: ref).artifact(fileFilter: fileFilter)
            }.value
            comparisonArtifacts[key] = semantic
            comparisonError = nil
        } catch {
            comparisonError = error.localizedDescription
        }
    }

    /// `comparisonGitRef` in HEAD/ref/custom mode, or the resolved merge-base of
    /// `comparisonBaseRef`/`comparisonGitRef` in pull-request mode (`nil` until resolved).
    private func oldComparisonKey(for diagram: GeneratedDiagram) -> ComparisonKey? {
        guard let ref = diagram.comparisonGitRef,
              let directory = codebase(for: diagram.codebaseID)?.directoryPath
        else { return nil }
        guard let baseRef = diagram.comparisonBaseRef else {
            return ComparisonKey(directory: directory, ref: ref)
        }
        guard let sha = resolvedMergeBases[MergeBaseKey(directory: directory, base: baseRef, head: ref)]
        else { return nil }
        return ComparisonKey(directory: directory, ref: sha)
    }

    /// `nil` in HEAD/ref/custom mode, where the "new" side is the live working tree instead
    /// (`artifact(for:)`).
    private func newComparisonKey(for diagram: GeneratedDiagram) -> ComparisonKey? {
        guard diagram.comparisonBaseRef != nil,
              let ref = diagram.comparisonGitRef,
              let directory = codebase(for: diagram.codebaseID)?.directoryPath
        else { return nil }
        return ComparisonKey(directory: directory, ref: ref)
    }

    /// Mirrors `artifact(for:)`'s own flatten + generated-type filter so delta mode diffs
    /// like-for-like (node ids must match the current side's display artifact).
    private func displayArtifact(for key: ComparisonKey) -> CodeArtifact? {
        guard let semantic = comparisonArtifacts[key] else { return nil }
        if let cached = comparisonDisplayCache[key] { return cached }
        let display = CodebaseAnalyzer()
            .flattenedForDisplay(semantic)
            .filteringGeneratedTypes(using: semantic.standardLanguageResolver)
        comparisonDisplayCache[key] = display
        return display
    }

    func comparisonArtifact(for diagram: GeneratedDiagram) -> CodeArtifact? {
        oldComparisonKey(for: diagram).flatMap(displayArtifact)
    }

    /// `nil` in HEAD/ref/custom mode or while still loading, in which case the caller should fall
    /// back to the codebase's current live artifact (`artifact(for:)`).
    func comparisonNewArtifact(for diagram: GeneratedDiagram) -> CodeArtifact? {
        newComparisonKey(for: diagram).flatMap(displayArtifact)
    }

    /// The historical-side counterpart of `semanticArtifact(for:)`, for recomputing findings
    /// against the comparison revision.
    func comparisonSemanticArtifact(for diagram: GeneratedDiagram) -> CodeArtifact? {
        oldComparisonKey(for: diagram).flatMap { comparisonArtifacts[$0] }
    }

    /// Mirrors `ensureAnalysisLoaded`'s shape but against the historical "old" artifact instead of
    /// the live one.
    func ensureComparisonAnalysisLoaded(for diagram: GeneratedDiagram) async {
        guard let key = oldComparisonKey(for: diagram), comparisonAnalyses[key] == nil,
              let semantic = comparisonArtifacts[key],
              let codebase = codebase(for: diagram.codebaseID)
        else { return }
        let configuration = codebase.qualityCheck
        let analysis = await Task.detached(priority: .userInitiated) {
            CodebaseAnalysis(artifact: semantic, configuration: configuration)
        }.value
        comparisonAnalyses[key] = analysis
    }

    func comparisonAnalysis(for diagram: GeneratedDiagram) -> CodebaseAnalysis? {
        oldComparisonKey(for: diagram).flatMap { comparisonAnalyses[$0] }
    }
}
