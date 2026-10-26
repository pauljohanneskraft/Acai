import AcaiCore
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
    private let rootDiscovery: any ProjectRootDiscovering

    @Published var source: Source = .localFolder {
        didSet { refreshCandidateClone() }
    }

    @Published var directoryURL: URL?
    @Published var securityScopedBookmark: SecurityScopedBookmark?
    /// The project roots found below `directoryURL`, and what the user chose to do with them. Only
    /// consulted when more than one was found — see `MultiRootPlan.isOffered`.
    @Published var plan = MultiRootPlan()
    @Published private(set) var discoveryPhase: AsyncOperationPhase = .idle
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
    private(set) var pendingDiscovery: Task<Void, Never>?
    private var checkedCandidate: URL?

    init(
        projectID: UUID, editor: ProjectCodebaseEditor, hubStoreDirectory: URL, remoteService: GitRemoteService,
        hostingService: GitHubHostingService, sizePolicy: CloneSizePolicy = .standard,
        listingDebounce: Duration = .milliseconds(500),
        rootDiscovery: any ProjectRootDiscovering = ProjectRootDiscoverer()
    ) {
        self.projectID = projectID
        self.editor = editor
        self.hubStoreDirectory = hubStoreDirectory
        self.remoteService = remoteService
        self.hostingService = hostingService
        self.sizePolicy = sizePolicy
        self.listingDebounce = listingDebounce
        self.rootDiscovery = rootDiscovery
    }

    // MARK: - What would be added

    /// The name a codebase gets from what it is: the repository it came from where there is one,
    /// otherwise the folder it lives in. The sheet has no name field — a name that isn't wanted is
    /// changed by renaming the codebase's row afterwards.
    var derivedName: String {
        switch source {
        case .localFolder:
            guard let directoryURL else { return "" }
            return LocalFolderCodebaseName(folderURL: directoryURL, repository: repositoryReference).value
        case .remoteURL:
            guard case .success(let remoteURL) = RemoteAddress(text: remoteAddress).result else { return "" }
            return RemoteRepositoryName(remoteURL: remoteURL).value
        case .gitHub:
            return selectedRepository?.name ?? ""
        }
    }

    /// What Clone would add, or `nil` while the chosen source isn't complete.
    var pendingClone: PendingClone? {
        switch source {
        case .localFolder:
            return nil
        case .remoteURL:
            guard case .success(let remoteURL) = RemoteAddress(text: remoteAddress).result,
                  let ref = selectedRemoteRef
            else { return nil }
            return PendingClone(name: derivedName, remoteURL: remoteURL, ref: ref, sizeKilobytes: nil)
        case .gitHub:
            guard let repository = selectedRepository, let ref = selectedRef, account != nil,
                  let remoteURL = gitHubRemoteURL(repository)
            else { return nil }
            return PendingClone(
                name: derivedName, remoteURL: remoteURL, ref: ref, sizeKilobytes: repository.sizeKilobytes)
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
        pendingDiscovery?.cancel()
    }
}

// MARK: - Project roots

extension NewCodebaseSheetModel {
    /// The codebases created, in discovery order, so the caller can select the first one
    /// deterministically through `ProjectBrowserViewModel.open(_:)`.
    func addLocalFolder() -> [UUID] {
        guard let directoryURL else { return [] }
        guard plan.isOffered, !plan.combinesIntoOne else {
            let id = editor.addCodebase(
                to: projectID, name: derivedName, directoryURL: directoryURL,
                securityScopedBookmark: securityScopedBookmark, repository: repositoryReference)
            return [id].compactMap { $0 }
        }
        return editor.insertCodebases(from: splitCodebaseFolders(directoryURL), to: projectID).addedIDs
    }

    /// Whether Add would create anything. A folder is enough, as it is for one project and for
    /// combining several, since every codebase takes its name from what it is. Splitting needs a
    /// checked root as well — unchecking them all would create nothing. Adding waits for the walk
    /// either way, so a folder of several projects cannot be added before it has asked.
    var canAddLocalFolder: Bool {
        guard directoryURL != nil, !discoveryPhase.isInFlight else { return false }
        guard plan.isOffered, !plan.combinesIntoOne else { return true }
        return plan.isSatisfiable
    }

    func setRootChecked(_ isChecked: Bool, for root: CodeArtifact.DiscoveredRoot) {
        plan.setChecked(isChecked, for: root)
    }

    /// Walks the picked folder for project roots. Starts over each time: the previous folder's roots
    /// and checkmarks are dropped before the walk, so the step can never offer one folder's roots
    /// while a different one is picked.
    func discoverRoots() {
        pendingDiscovery?.cancel()
        plan = MultiRootPlan()
        guard let folder = directoryURL else {
            discoveryPhase = .idle
            return
        }
        let access = ScopedResourceAccess(path: folder.path, bookmark: securityScopedBookmark)
        let discoverer = rootDiscovery
        discoveryPhase = .loading(.app("View.NewCodebaseSheet.FindingProjects"))
        pendingDiscovery = Task { [weak self] in
            let roots = await Task.detached(priority: .userInitiated) {
                await access.whileAccessible { discoverer.discoverRoots(in: folder) }
            }.value
            guard let self, !Task.isCancelled, directoryURL == folder else { return }
            plan = MultiRootPlan(roots: roots, checkedPaths: Set(roots.map(\.path)))
            discoveryPhase = .loaded
        }
    }

    /// A child root gets its **own** bookmark rather than the picked folder's: a bookmark resolves to
    /// the location it was minted for, so reusing the parent's would point every split codebase back
    /// at the parent tree. Minting one for a child is only possible inside an open scope on the
    /// parent, which is what `withResolvedURL` holds here.
    private func splitCodebaseFolders(_ folder: URL) -> [DroppedFolder] {
        let access = ScopedResourceAccess(path: folder.path, bookmark: securityScopedBookmark)
        let plan = plan
        let bookmark = securityScopedBookmark
        let repository = repositoryReference
        return (try? access.withResolvedURL { resolved in
            plan.folders(under: resolved).map { child in
                child == resolved
                    ? DroppedFolder(url: child, securityScopedBookmark: bookmark, repository: repository)
                    : DroppedFolder(url: child, securityScopedBookmark: try? SecurityScopedBookmark(resolving: child))
            }
        }) ?? plan.folders(under: folder).map { DroppedFolder(url: $0) }
    }
}
