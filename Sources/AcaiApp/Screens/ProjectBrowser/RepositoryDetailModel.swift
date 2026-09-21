import Combine
import Foundation

/// One shared hub clone as the Repository detail shows it: what is on disk, and which codebases
/// reference it. Both follow the store — the codebase list as `projects` changes, the on-disk
/// state whenever `ProjectStore.repositoryChanges` names this remote.
@MainActor
final class RepositoryDetailModel: ObservableObject {
    let remoteURL: URL

    @Published private(set) var onDiskSize: Int64?
    @Published private(set) var lastFetchedAt: Date?
    @Published private(set) var worktreeNames: [String] = []
    @Published private(set) var isShallow = false
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var isFetching = false
    @Published private(set) var referencingCodebases: [Codebase] = []
    @Published var errorMessage: String?

    private let store: ProjectStore
    private let remoteService: GitRemoteService
    private var subscriptions: Set<AnyCancellable> = []
    private var reload: Task<Void, Never>?

    init(remoteURL: URL, store: ProjectStore, remoteService: GitRemoteService) {
        self.remoteURL = remoteURL
        self.store = store
        self.remoteService = remoteService
        referencingCodebases = RepositoryIndex(projects: store.projects).codebases(referencing: remoteURL)
        let identity = RemoteIdentity(remoteURL: remoteURL)
        store.$projects
            .map { RepositoryIndex(projects: $0).codebases(referencing: remoteURL) }
            .sink { [weak self] codebases in
                MainActor.assumeIsolated { self?.referencingCodebases = codebases }
            }
            .store(in: &subscriptions)
        store.repositoryChanges
            .filter { RemoteIdentity(remoteURL: $0) == identity }
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            .store(in: &subscriptions)
    }

    private var endpoint: RemoteEndpoint {
        RemoteEndpoint(remoteURL: remoteURL, gitHubCredential: nil)
    }

    /// Single-flight: a load started later supersedes one still in flight, so the details never
    /// settle on an older inspection.
    func loadDetails() async {
        reload?.cancel()
        let load = Task { [weak self] in
            guard let self else { return }
            await performLoad()
        }
        reload = load
        await load.value
    }

    private func performLoad() async {
        isLoadingDetails = true
        defer { if !Task.isCancelled { isLoadingDetails = false } }
        let hubStoreDirectory = store.gitRepositoriesDir
        async let inspection = remoteService.inspectClone(endpoint, hubStoreDirectory: hubStoreDirectory)
        async let size = remoteService.onDiskSize(of: endpoint, hubStoreDirectory: hubStoreDirectory)
        let (loaded, loadedSize) = await (inspection, size)
        guard !Task.isCancelled else { return }
        isShallow = loaded.isShallow
        lastFetchedAt = loaded.lastFetchedAt
        worktreeNames = loaded.worktreeNames
        onDiskSize = loadedSize
    }

    /// Registered with the activity center, so it shows in the global Activity indicator and flips
    /// this repository's sidebar row to a spinner, the same as a codebase's fetch does.
    func fetchNow() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        let remoteService = self.remoteService
        let endpoint = RemoteEndpoint(remoteURL: remoteURL)
        let hubStoreDirectory = store.gitRepositoriesDir
        let locks = store.gitRepositoryLocks
        do {
            _ = try await store.activityCenter.run(
                title: .app("Activity.FetchingRemote \(remoteURL.lastPathComponent)"),
                kind: .gitFetch, subject: .repository(remoteURL)
            ) { onProgress in
                try await remoteService.fetch(
                    endpoint, hubStoreDirectory: hubStoreDirectory, locks: locks, onProgress: onProgress)
            }
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleReload() {
        Task { [weak self] in await self?.loadDetails() }
    }
}
