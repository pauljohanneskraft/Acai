import AcaiCore
import AcaiGit
import Foundation

/// Loads the churn data off the main actor (this is a git-history walk, real filesystem/
/// object-store work) and joins it with already-computed complexity into
/// `HotspotChartData`. `artifact` is captured once at construction (not recomputed on every
/// render); only the churn half is asynchronous.
@MainActor
final class HotspotViewModel: ObservableObject {
    @Published private(set) var chartData: HotspotChartData?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    /// `false` once loading finishes and no git history could be found at all (as opposed to a real
    /// repository that simply has none to report) — distinguishes the "not a git repo"/"not yet
    /// cloned" empty state from a genuinely-empty chart.
    @Published private(set) var hasGitHistory = true
    /// The repository is a shallow clone: its churn would count only the commits that happen to
    /// be present, so no chart is drawn until the full history has been fetched.
    @Published private(set) var isHistoryNotFetched = false

    private let artifact: CodeArtifact

    init(artifact: CodeArtifact) {
        self.artifact = artifact
    }

    func load(codebase: Codebase, gitRepositoriesDir: URL) async {
        isLoading = true
        loadError = nil
        isHistoryNotFetched = false
        defer { isLoading = false }
        let resolver = HotspotChurnResolver(codebase: codebase, gitRepositoriesDir: gitRepositoriesDir)
        do {
            let churn = try await Task.detached(priority: .userInitiated) {
                try resolver.churnByFile()
            }.value
            guard let churn else {
                hasGitHistory = false
                chartData = nil
                return
            }
            hasGitHistory = true
            chartData = HotspotChartData(artifact: artifact, churnByFile: churn)
        } catch is HistoryNotFetched {
            chartData = nil
            isHistoryNotFetched = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}
