import AcaiGit
import Foundation

/// One finding's line — what a blame request asks about and what its answer keys on. Declared
/// outside the `@MainActor` view model so it crosses into the detached walk without question.
struct FindingBlameLine: Hashable, Sendable {
    let codebaseID: UUID
    let path: String
    let line: Int
}

/// Line authorship for the findings list, walked off the main actor once the list is already on
/// screen: rows render immediately and gain their "last changed by" line when git answers, so a
/// large history never delays the findings themselves.
@MainActor
final class FindingsBlameViewModel: ObservableObject {
    @Published private(set) var lastTouchedByFindingID: [String: GitBlame.Line] = [:]

    /// What a load is for. Compared against the last completed one so a list that merely re-renders
    /// doesn't walk history again, and so a slow walk finishing after a newer one can't win.
    struct Request: Equatable {
        /// Grouped by codebase and then by file, so each file is blamed exactly once however many
        /// findings it carries.
        let linesByCodebase: [UUID: [String: Set<Int>]]
        /// Two findings can share a line, so each one maps back to the same answer.
        let findingIDsByLine: [FindingBlameLine: [String]]

        init(findings: [Finding]) {
            var linesByCodebase: [UUID: [String: Set<Int>]] = [:]
            var findingIDsByLine: [FindingBlameLine: [String]] = [:]
            for finding in findings {
                guard let location = finding.location, location.line > 0 else { continue }
                linesByCodebase[finding.codebaseID, default: [:]][location.filePath, default: []]
                    .insert(location.line)
                let key = FindingBlameLine(
                    codebaseID: finding.codebaseID, path: location.filePath, line: location.line)
                findingIDsByLine[key, default: []].append(finding.id)
            }
            self.linesByCodebase = linesByCodebase
            self.findingIDsByLine = findingIDsByLine
        }
    }

    private var loadedRequest: Request?

    func load(findings: [Finding], codebases: [UUID: Codebase], gitRepositoriesDir: URL) async {
        // The list grows as each codebase's analysis lands, so settle before walking history —
        // otherwise every partial list starts a walk the next one immediately supersedes.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        let request = Request(findings: findings)
        guard request != loadedRequest else { return }
        guard !request.linesByCodebase.isEmpty else {
            lastTouchedByFindingID = [:]
            loadedRequest = request
            return
        }

        let work = request.linesByCodebase.compactMap { codebaseID, linesByFile in
            codebases[codebaseID].map { (id: codebaseID, codebase: $0, lines: linesByFile) }
        }
        let resolved = await Task.detached(priority: .userInitiated) {
            work.reduce(into: [FindingBlameLine: GitBlame.Line]()) { result, entry in
                let resolver = FindingBlameResolver(
                    codebase: entry.codebase, gitRepositoriesDir: gitRepositoriesDir)
                // A codebase with no repository, none cloned yet, or only a shallow cut of one
                // contributes nothing: the row omits authorship rather than showing a gap or an
                // error, and `GitBlame` has already dropped the per-file failures on its own.
                guard let blamed = try? resolver.lastTouched(linesByFile: entry.lines) else { return }
                for (path, byLine) in blamed {
                    for (line, authorship) in byLine {
                        result[FindingBlameLine(codebaseID: entry.id, path: path, line: line)] = authorship
                    }
                }
            }
        }.value
        guard !Task.isCancelled else { return }

        lastTouchedByFindingID = request.findingIDsByLine.reduce(into: [String: GitBlame.Line]()) {
            result, entry in
            guard let authorship = resolved[entry.key] else { return }
            for id in entry.value { result[id] = authorship }
        }
        loadedRequest = request
    }
}
