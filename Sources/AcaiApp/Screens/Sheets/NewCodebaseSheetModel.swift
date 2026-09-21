import AcaiGit
import Foundation

/// The Add Codebase sheet's state and rules: which source is chosen and what it would add, the
/// remote's branch listing (read once typing pauses, a result for an older address discarded),
/// the account's repositories, and whether a clone has to be asked about first.
@MainActor
final class NewCodebaseSheetModel: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case localFolder
        case remoteURL
        case gitHub
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .localFolder:
                .app("View.NewCodebaseSheet.SourceLocalFolder")
            case .remoteURL:
                .app("View.NewCodebaseSheet.SourceRemoteURL")
            case .gitHub:
                .app("View.NewCodebaseSheet.SourceGitHub")
            }
        }
    }

    let projectID: UUID
    private let editor: ProjectCodebaseEditor
    private let hubStoreDirectory: URL
    private let remoteService: GitRemoteService
    private let hostingService: GitHubHostingService
    private let sizePolicy: CloneSizePolicy
    private let listingDebounce: Duration

    @Published var source: Source = .localFolder {
        didSet { refreshCandidateClone() }
    }
    @Published var name = ""

    @Published var directoryURL: URL?
    @Published var securityScopedBookmark: SecurityScopedBookmark?
    /// Set when the picked folder turns out to already be a git working directory with an
    /// `origin` remote. `nil` for a plain folder.
    @Published var repositoryReference: CodebaseRepositoryReference?

    @Published var remoteAddress = "" {
        didSet { if oldValue != remoteAddress { addressChanged() } }
    }
    @Published private(set) var remoteListing: RemoteListingState = .idle
    @Published var selectedRemoteRef: GitCheckout.Ref?

    @Published var account: GitHubTokenStore.StoredAccount? {
        didSet { refreshCandidateClone() }
    }
    @Published private(set) var repositories: [GitHubAPIClient.Repository] = []
    @Published var selectedRepository: GitHubAPIClient.Repository? {
        didSet { if oldValue != selectedRepository { repositoryChanged() } }
    }
    @Published private(set) var refs: [GitCheckout.Ref] = []
    @Published var selectedRef: GitCheckout.Ref?
    @Published private(set) var isLoadingRepositories = false
    @Published private(set) var isLoadingRefs = false
    @Published private(set) var gitHubErrorMessage: String?

    @Published private(set) var clonePhase: AsyncOperationPhase = .idle
    @Published var pendingLargeClone: PendingClone?
    @Published private(set) var isCandidateAlreadyCloned = false

    /// The work an input change started, so a caller can await it instead of guessing a delay.
    private(set) var pendingListing: Task<Void, Never>?
    private(set) var pendingCloneCheck: Task<Void, Never>?
    private(set) var pendingRefs: Task<Void, Never>?
    private var checkedCandidate: URL?

    init(
        projectID: UUID, editor: ProjectCodebaseEditor, hubStoreDirectory: URL, remoteService: GitRemoteService,
        hostingService: GitHubHostingService, sizePolicy: CloneSizePolicy = .standard,
        listingDebounce: Duration = .milliseconds(500)
    ) {
        self.projectID = projectID
        self.editor = editor
        self.hubStoreDirectory = hubStoreDirectory
        self.remoteService = remoteService
        self.hostingService = hostingService
        self.sizePolicy = sizePolicy
        self.listingDebounce = listingDebounce
    }

    // MARK: - What would be added

    /// What Clone would add, or `nil` while the chosen source isn't complete.
    var pendingClone: PendingClone? {
        switch source {
        case .localFolder:
            return nil
        case .remoteURL:
            guard case .success(let remoteURL) = RemoteAddress(text: remoteAddress).result,
                  let ref = selectedRemoteRef
            else { return nil }
            let fallbackName = remoteURL.deletingPathExtension().lastPathComponent
            return PendingClone(
                name: name.isEmpty ? fallbackName : name, remoteURL: remoteURL, ref: ref, sizeKilobytes: nil)
        case .gitHub:
            guard let repository = selectedRepository, let ref = selectedRef, account != nil,
                  let remoteURL = gitHubRemoteURL(repository)
            else { return nil }
            return PendingClone(
                name: name.isEmpty ? repository.name : name, remoteURL: remoteURL, ref: ref,
                sizeKilobytes: repository.sizeKilobytes)
        }
    }

    /// The remote the chosen source points at, known before its ref is.
    var candidateRemoteURL: URL? {
        switch source {
        case .localFolder:
            nil
        case .remoteURL:
            RemoteAddress(text: remoteAddress).validURL
        case .gitHub:
            selectedRepository.flatMap(gitHubRemoteURL)
        }
    }

    /// Adding attaches a new worktree to the existing shared clone instead of cloning.
    func isAlreadyCloned(_ remoteURL: URL?) -> Bool {
        remoteURL != nil && isCandidateAlreadyCloned
    }

    /// The credential-free URL `CodebaseRepositoryReference.remoteURL` ends up storing.
    func gitHubRemoteURL(_ repository: GitHubAPIClient.Repository) -> URL? {
        guard let account else { return nil }
        return GitHubRemote(credential: account.credential, owner: repository.owner.login, repo: repository.name)
            .plainURL
    }

    // MARK: - Cloning

    /// `true` once the codebase was added and the sheet can close; `false` when a large repository
    /// is being asked about first (`pendingLargeClone`). Adding to an existing shared clone never
    /// asks, since nothing is downloaded.
    func requestClone(_ pending: PendingClone) async -> Bool {
        if !isAlreadyCloned(pending.remoteURL), sizePolicy.warrantsWarning(sizeKilobytes: pending.sizeKilobytes) {
            pendingLargeClone = pending
            return false
        }
        await clone(pending, depth: .full)
        return true
    }

    func clone(_ pending: PendingClone, depth: GitHistoryDepth) async {
        clonePhase = .loading(.app("View.NewCodebaseSheet.Cloning"))
        await editor.addRemoteCodebase(
            to: projectID, name: pending.name, remoteURL: pending.remoteURL, ref: pending.ref.name,
            refKind: pending.ref.kind, depth: depth)
        clonePhase = .loaded
    }

    func addLocalFolder() {
        guard let directoryURL else { return }
        editor.addCodebase(
            to: projectID, name: name, directoryURL: directoryURL,
            securityScopedBookmark: securityScopedBookmark, repository: repositoryReference)
    }

    private func refreshCandidateClone() {
        let candidate = candidateRemoteURL
        guard candidate != checkedCandidate else { return }
        checkedCandidate = candidate
        pendingCloneCheck?.cancel()
        guard let candidate else {
            isCandidateAlreadyCloned = false
            return
        }
        pendingCloneCheck = Task { [weak self] in
            guard let self else { return }
            let endpoint = RemoteEndpoint(remoteURL: candidate, gitHubCredential: nil)
            let inspection = await remoteService.inspectClone(endpoint, hubStoreDirectory: hubStoreDirectory)
            guard !Task.isCancelled else { return }
            isCandidateAlreadyCloned = inspection.isCloned
        }
    }

    // MARK: - Remote URL

    /// A keystroke drops the listing in flight; an invalid address never reaches the remote, and a
    /// valid one is neither listed nor inspected on disk until typing pauses.
    private func addressChanged() {
        pendingListing?.cancel()
        pendingListing = nil
        selectedRemoteRef = nil
        guard !remoteAddress.isEmpty else {
            remoteListing = .idle
            refreshCandidateClone()
            return
        }
        if case .failure(let problem) = RemoteAddress(text: remoteAddress).result {
            remoteListing = .invalid(problem)
            refreshCandidateClone()
            return
        }
        pendingListing = Task { [weak self, listingDebounce] in
            if listingDebounce > .zero {
                guard (try? await Task.sleep(for: listingDebounce)) != nil else { return }
            }
            guard let self else { return }
            refreshCandidateClone()
            await listRemote()
        }
    }

    func listRemote() async {
        guard case .success(let remoteURL) = RemoteAddress(text: remoteAddress).result else { return }
        let address = remoteAddress
        remoteListing = .loading
        do {
            let listing = try await remoteService.listRemote(RemoteEndpoint(remoteURL: remoteURL))
            guard address == remoteAddress, !Task.isCancelled else { return }
            remoteListing = .loaded(listing.refs)
            selectedRemoteRef = listing.refs.first { $0.kind == .branch && $0.name == listing.defaultBranch }
                ?? listing.refs.first
        } catch {
            guard address == remoteAddress, !Task.isCancelled else { return }
            remoteListing = .failed(
                String(localized: .app("View.NewCodebaseSheet.CouldNotReadRemote \(error.localizedDescription)")))
        }
    }

    // MARK: - GitHub

    func loadRepositories() async {
        guard let account else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            repositories = try await hostingService.repositories(credential: account.credential)
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }

    private func repositoryChanged() {
        refreshCandidateClone()
        pendingRefs?.cancel()
        guard let selectedRepository else { return }
        pendingRefs = Task { [weak self] in await self?.loadRefs(for: selectedRepository) }
    }

    private func loadRefs(for repository: GitHubAPIClient.Repository) async {
        guard let remoteURL = gitHubRemoteURL(repository) else { return }
        isLoadingRefs = true
        defer { isLoadingRefs = false }
        do {
            let endpoint = RemoteEndpoint(remoteURL: remoteURL, gitHubCredential: account?.credential)
            let loaded = try await remoteService.listRemote(endpoint).refs
            guard !Task.isCancelled else { return }
            refs = loaded
            selectedRef = refs.first { $0.kind == .branch && $0.name == repository.defaultBranch } ?? refs.first
        } catch {
            guard !Task.isCancelled else { return }
            gitHubErrorMessage = error.localizedDescription
        }
    }

    /// Dismissing the sheet drops whatever it was still reading.
    func cancelPendingWork() {
        pendingListing?.cancel()
        pendingCloneCheck?.cancel()
        pendingRefs?.cancel()
    }
}
