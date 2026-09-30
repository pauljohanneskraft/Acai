import AcaiGit
import Foundation

/// One finding's declaration — what a blame request asks about and what its answer keys on. Declared
/// outside the `@MainActor` view model so it crosses into the detached walk without question.
struct FindingBlameRange: Hashable, Sendable {
    let codebaseID: UUID
    let path: String
    let lines: ClosedRange<Int>
}

/// Every codebase's blame, one after another, stopping between codebases and between files once the
/// task running it is cancelled.
struct FindingsBlameWalk: Sendable {
    struct Entry: Sendable {
        let codebaseID: UUID
        let codebase: Codebase
        let rangesByFile: [String: Set<ClosedRange<Int>>]
    }

    struct Outcome: Sendable {
        var lastTouched: [FindingBlameRange: GitBlame.Line] = [:]
        var historyNotFetched: Set<UUID> = []
        /// The first unexpected failure; a codebase with no history at all is not one.
        var failure: String?
    }

    let entries: [Entry]
    let gitRepositoriesDir: URL

    func run() throws -> Outcome {
        var outcome = Outcome()
        for entry in entries {
            try Task.checkCancellation()
            let resolver = FindingBlameResolver(codebase: entry.codebase, gitRepositoriesDir: gitRepositoriesDir)
            do {
                switch try resolver.lastTouched(rangesByFile: entry.rangesByFile) {
                case .blamed(let blamed):
                    for (path, byRange) in blamed {
                        for (lines, authorship) in byRange {
                            let key = FindingBlameRange(codebaseID: entry.codebaseID, path: path, lines: lines)
                            outcome.lastTouched[key] = authorship
                        }
                    }
                case .noHistory:
                    break
                case .historyNotFetched:
                    outcome.historyNotFetched.insert(entry.codebaseID)
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                outcome.failure = outcome.failure ?? error.localizedDescription
            }
        }
        return outcome
    }
}

/// Line authorship for the findings list, walked off the main actor once the list is already on
/// screen: rows render immediately and gain their "last changed by" line when git answers, so a
/// large history never delays the findings themselves.
@MainActor
final class FindingsBlameViewModel: ObservableObject {
    @Published private(set) var lastTouchedByFindingID: [String: GitBlame.Line] = [:]
    /// Codebases cloned without full history, which can't answer rather than answering wrongly.
    @Published private(set) var historyNotFetchedCodebaseIDs: Set<UUID> = []
    @Published private(set) var phase: AsyncOperationPhase = .idle

    /// What a load is for. Compared against the last completed one so a list that merely re-renders
    /// doesn't walk history again, and so a slow walk finishing after a newer one can't win.
    struct Request: Equatable {
        /// Grouped by codebase and then by file, so each file is blamed exactly once however many
        /// findings it carries.
        let rangesByCodebase: [UUID: [String: Set<ClosedRange<Int>>]]
        /// Two findings can share a declaration, so each one maps back to the same answer.
        let findingIDsByRange: [FindingBlameRange: [String]]

        init(findings: [Finding]) {
            var rangesByCodebase: [UUID: [String: Set<ClosedRange<Int>>]] = [:]
            var findingIDsByRange: [FindingBlameRange: [String]] = [:]
            for finding in findings {
                guard let location = finding.location, location.line > 0 else { continue }
                let lines = location.line...max(location.endLine ?? location.line, location.line)
                rangesByCodebase[finding.codebaseID, default: [:]][location.filePath, default: []].insert(lines)
                let key = FindingBlameRange(codebaseID: finding.codebaseID, path: location.filePath, lines: lines)
                findingIDsByRange[key, default: []].append(finding.id)
            }
            self.rangesByCodebase = rangesByCodebase
            self.findingIDsByRange = findingIDsByRange
        }
    }

    private var loadedRequest: Request?
    private var loadedPhase: AsyncOperationPhase = .idle

    /// Forgets the last answer, so the next `load` walks history again even for the same findings —
    /// after a retry, or once a shallow clone has fetched its full history.
    func invalidate() {
        loadedRequest = nil
    }

    func load(findings: [Finding], codebases: [UUID: Codebase], gitRepositoriesDir: URL) async {
        // The list grows as each codebase's analysis lands, so settle before walking history —
        // otherwise every partial list starts a walk the next one immediately supersedes.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        let request = Request(findings: findings)
        guard request != loadedRequest else {
            phase = loadedPhase
            return
        }
        let blameWalk = FindingsBlameWalk(
            entries: request.rangesByCodebase.compactMap { codebaseID, rangesByFile in
                codebases[codebaseID].map { .init(codebaseID: codebaseID, codebase: $0, rangesByFile: rangesByFile) }
            },
            gitRepositoriesDir: gitRepositoriesDir)
        phase = .loading(.app("View.FindingsView.ReadingAuthorship"))

        let walk = Task.detached(priority: .userInitiated) { try blameWalk.run() }
        let finished: FindingsBlameWalk.Outcome
        do {
            finished = try await withTaskCancellationHandler {
                try await walk.value
            } onCancel: {
                walk.cancel()
            }
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        lastTouchedByFindingID = request.findingIDsByRange
            .reduce(into: [String: GitBlame.Line]()) { result, entry in
                guard let authorship = finished.lastTouched[entry.key] else { return }
                for id in entry.value { result[id] = authorship }
            }
        historyNotFetchedCodebaseIDs = finished.historyNotFetched
        phase = finished.failure.map {
            .failed(String(localized: .app("View.FindingsView.CouldNotReadAuthorship \($0)")))
        } ?? .loaded
        loadedPhase = phase
        loadedRequest = request
    }
}
