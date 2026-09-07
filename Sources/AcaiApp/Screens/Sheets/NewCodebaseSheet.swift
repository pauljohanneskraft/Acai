import AcaiGit
import SwiftUI
import UniformTypeIdentifiers

struct NewCodebaseSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case localFolder = "Local Folder"
        case gitHub = "From GitHub"
        var id: String { rawValue }
    }

    let projectID: UUID
    private let repositoryService: GitHubRepositoryService
    @EnvironmentObject private var model: ProjectBrowserViewModel
    // Reads signed-in state from the shared store, so signing in/out in Settings is reflected
    // here immediately — see `gitHubSection` for the signed-out prompt.
    @EnvironmentObject private var accountStore: GitHubAccountStore
    @EnvironmentObject private var settingsPresenter: SettingsPresenter
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    /// Defaults to the real network implementation, swapped for `FixtureGitHubRepositoryService`
    /// under a UI test fixture — see `GitHubRepositoryService`.
    init(projectID: UUID, repositoryService: GitHubRepositoryService? = nil) {
        self.projectID = projectID
        self.repositoryService = repositoryService ?? GitHubRepositoryServiceResolver().resolve()
    }

    @State private var source: Source = .localFolder
    @State private var name = ""
    @FocusState private var isNameFieldFocused: Bool

    @State private var directoryURL: URL?
    @State private var securityScopedBookmark: SecurityScopedBookmark?
    @State private var isChoosingDirectory = false
    /// Set when the picked folder turns out to already be a git working directory with an
    /// `origin` remote — the transparent local-folder upgrade. `nil` for a plain folder.
    @State private var repositoryReference: CodebaseRepositoryReference?

    @State private var repositories: [GitHubAPIClient.Repository] = []
    @State private var repositorySearch = ""
    @State private var selectedRepository: GitHubAPIClient.Repository?
    @State private var refs: [GitHubRef] = []
    @State private var selectedRef: GitHubRef?
    @State private var isLoadingRepositories = false
    @State private var isLoadingRefs = false
    @State private var clonePhase: AsyncOperationPhase = .idle
    @State private var gitHubErrorMessage: String?

    private var account: GitHubTokenStore.StoredAccount? { accountStore.account }

    var body: some View {
        NavigationStack {
            Form {
                Picker(.app("View.NewCodebaseSheet.Source"), selection: $source) {
                    ForEach(Source.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("newCodebase.sourcePicker")

                switch source {
                case .localFolder:
                    localFolderSection
                case .gitHub:
                    gitHubSection
                }
            }
            #if os(macOS)
            // The default (`.automatic`) form style on macOS renders rows flush against each other
            // with no card background or breathing room between sections — `.grouped` is what gives
            // this the same visually-separated, padded section look `NewProjectSheet`'s single
            // section already gets "for free" (a lone `Section` needs no grouping to look fine; this
            // sheet's multiple sections do).
            .formStyle(.grouped)
            .frame(maxWidth: 480)
            #else
            // A single `.large` detent, not `[.medium, .large]`: the GitHub tab's content (source
            // picker + account section + name/search fields + repository/ref pickers) is taller
            // than `.medium` fits, and starting collapsed at `.medium` left the repository picker
            // genuinely absent from the accessibility tree below the fold — not just scrolled past.
            .presentationDetents([.large])
            #endif
            .onAppear { isNameFieldFocused = true }
            .navigationTitle(.app("View.NewCodebaseSheet.AddCodebase"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.NewCodebaseSheet.Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
            .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
                guard let url = try? result.get() else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    model.store.report(.app("Error.ScopedResourceAccess.Denied \(url.path)"))
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                directoryURL = url
                // A bookmark that silently failed to mint is what breaks access after relaunch,
                // so report it rather than storing `nil`.
                do {
                    securityScopedBookmark = try SecurityScopedBookmark(resolving: url)
                } catch {
                    securityScopedBookmark = nil
                    model.store.report(
                        .app("Error.ScopedResourceAccess.BookmarkFailed \(url.path) \(error.localizedDescription)"))
                }
                // Detecting a `.git` root reads the repository's config/HEAD, so it must happen
                // inside this same security-scoped access window.
                repositoryReference = LocalGitRepositoryDetector(directory: url).detect()
            }
            // `.task(id:)`, not `.onChange(of:)`: `account` is typically already non-nil the
            // *first* time this sheet appears, so `.onChange` (which only fires on a later
            // transition) would never fire. `.task(id:)` runs immediately on appear and re-runs
            // on change, covering both cases.
            .task(id: account?.login) {
                guard account != nil else { return }
                await loadRepositories()
            }
            .onChange(of: selectedRepository) { _, newValue in
                if let newValue { Task { await loadRefs(for: newValue) } }
            }
        }
    }

    private var localFolderSection: some View {
        Section {
            #if os(macOS)
            // Not a bare `TextField(text:label:)`: inside a macOS `Form`, a `TextField`'s own title
            // renders as an extra leading label rather than an internal placeholder, misaligning it
            // against an explicit `LabeledContent` row like this one. `prompt:` is unambiguously
            // internal placeholder text.
            LabeledContent {
                TextField("", text: $name, prompt: Text(.app("View.NewCodebaseSheet.EGMyLibrary")))
                    .multilineTextAlignment(.trailing)
                    .focused($isNameFieldFocused)
                    .accessibilityIdentifier("newCodebase.localNameField")
            } label: {
                Text(.app("View.NewCodebaseSheet.Name"))
            }
            LabeledContent {
                HStack {
                    directoryPathText
                    Button(.app("View.NewCodebaseSheet.Choose")) { isChoosingDirectory = true }
                        .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
                }
            } label: {
                Text(.app("View.NewCodebaseSheet.Directory"))
            }
            #else
            TextField(text: $name) {
                Text(.app("View.NewCodebaseSheet.Name"))
            }
            .focused($isNameFieldFocused)
            .accessibilityIdentifier("newCodebase.localNameField")
            HStack {
                directoryPathText
                Spacer()
                Button(.app("View.NewCodebaseSheet.Choose")) { isChoosingDirectory = true }
                    .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
            }
            #endif
        }
    }

    private var directoryPathText: some View {
        (directoryURL.map { Text(verbatim: $0.path) }
            ?? Text(.app("View.NewCodebaseSheet.NoDirectoryChosen")))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(directoryURL == nil ? .secondary : .primary)
    }

    @ViewBuilder
    private var gitHubSection: some View {
        Section {
            if let account {
                // Read-only summary — the full sign-in/scopes/expiry UI lives in Settings; this
                // just confirms who's signed in and lets you jump there for anything more.
                HStack {
                    Text(.app("View.NewCodebaseSheet.Signed \(account.login)"))
                        .accessibilityIdentifier("newCodebase.signedInAsLabel")
                    Spacer()
                    settingsLinkButton
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(.app("View.NewCodebaseSheet.SignGitHubSettings"))
                        .foregroundStyle(.secondary)
                    settingsLinkButton
                }
            }
        }
        if account != nil {
            Section {
                #if os(macOS)
                // Same `prompt:` fix as `localFolderSection` — see its comment.
                LabeledContent {
                    TextField("", text: $name, prompt: Text(.app("View.NewCodebaseSheet.Optional")))
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("newCodebase.nameField")
                } label: {
                    Text(.app("View.NewCodebaseSheet.Name"))
                }
                LabeledContent {
                    TextField(
                        "", text: $repositorySearch, prompt: Text(.app("View.NewCodebaseSheet.SearchRepositories"))
                    )
                    .multilineTextAlignment(.trailing)
                } label: {
                    Text(.app("View.NewCodebaseSheet.Search"))
                }
                #else
                TextField(text: $name) {
                    Text(.app("View.NewCodebaseSheet.NameOptional"))
                }
                .accessibilityIdentifier("newCodebase.nameField")
                TextField(text: $repositorySearch) {
                    Text(.app("View.NewCodebaseSheet.SearchRepositories"))
                }
                #endif
                if isLoadingRepositories {
                    ProgressView()
                } else {
                    Picker(.app("View.NewCodebaseSheet.Repository"), selection: $selectedRepository) {
                        Text(.app("View.NewCodebaseSheet.None")).tag(GitHubAPIClient.Repository?.none)
                        ForEach(filteredRepositories) { repository in
                            Text(verbatim: repository.fullName).tag(Optional(repository))
                        }
                    }
                    .accessibilityIdentifier("newCodebase.repositoryPicker")
                }
                if selectedRepository != nil {
                    if isLoadingRefs {
                        ProgressView()
                    } else {
                        Picker(.app("View.NewCodebaseSheet.BranchTag"), selection: $selectedRef) {
                            ForEach(refs) { ref in
                                Text(verbatim: ref.name).tag(Optional(ref))
                            }
                        }
                        .accessibilityIdentifier("newCodebase.refPicker")
                    }
                }
                // This remote already has a shared hub clone on disk (from an earlier codebase
                // referencing it) — adding this one attaches a new worktree to it instead of a
                // fresh network clone, so it's fast regardless of repository size.
                if isSelectedRepositoryAlreadyCloned {
                    Label(
                        .app("View.NewCodebaseSheet.AlreadyClonedLocally"),
                        systemImage: "checkmark.icloud"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("newCodebase.alreadyClonedHint")
                }
            }
        }
        if let gitHubErrorMessage {
            Section {
                Text(verbatim: gitHubErrorMessage).foregroundStyle(.red)
            }
        }
    }

    /// Jumps straight to the Settings surface that now owns sign-in — macOS opens the real
    /// `Settings` scene via `\.openSettings`; iPad/iPhone dismiss this sheet and present the
    /// Settings sheet instead, since a sheet can't stack on top of another sheet's own presentation
    /// cleanly on those platforms.
    private var settingsLinkButton: some View {
        Button(.app("View.NewCodebaseSheet.OpenSettings")) {
            #if os(macOS)
            openSettings()
            #else
            dismiss()
            settingsPresenter.isPresented = true
            #endif
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("newCodebase.openSettingsButton")
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch source {
        case .localFolder:
            Button(.app("View.NewCodebaseSheet.Add")) {
                if let dir = directoryURL {
                    model.editing.addCodebase(
                        to: projectID, name: name, directoryURL: dir,
                        securityScopedBookmark: securityScopedBookmark, repository: repositoryReference)
                }
                dismiss()
            }
            .disabled(name.isEmpty || directoryURL == nil)
            .accessibilityIdentifier("newCodebase.addButton")
        case .gitHub:
            // "Add" once the repository already has a local hub clone (this will attach a
            // worktree, not start a fresh network clone) — "Clone" the first time.
            Button(isSelectedRepositoryAlreadyCloned
                ? .app("View.NewCodebaseSheet.Add")
                : .app("View.NewCodebaseSheet.Clone")) {
                guard let repository = selectedRepository, let ref = selectedRef, let account,
                      !clonePhase.isInFlight else { return }
                clonePhase = .loading(.app("View.NewCodebaseSheet.Cloning"))
                Task {
                    await model.editing.addGitHubCodebase(
                        to: projectID,
                        name: name.isEmpty ? repository.name : name,
                        credential: account.credential,
                        target: GitHubRepositoryRef(
                            owner: repository.owner.login, repo: repository.name, ref: ref.name, kind: ref.kind)
                    )
                    clonePhase = .loaded
                    dismiss()
                }
            }
            .disabled(selectedRepository == nil || selectedRef == nil || account == nil || clonePhase.isInFlight)
            .accessibilityIdentifier("newCodebase.cloneButton")
            AsyncOperationStatusView(identifierPrefix: "newCodebase.clone", phase: clonePhase)
        }
    }

    /// Checked against the plain (credential-free) remote URL `GitHubRepositoryClone` would build
    /// for this repository — the same one `CodebaseRepositoryReference.remoteURL` ends up storing.
    private var isSelectedRepositoryAlreadyCloned: Bool {
        guard let repository = selectedRepository, account != nil else { return false }
        var plainRemoteURLComponents = URLComponents()
        plainRemoteURLComponents.scheme = "https"
        plainRemoteURLComponents.host = "github.com"
        plainRemoteURLComponents.path = "/\(repository.owner.login)/\(repository.name).git"
        guard let plainRemoteURL = plainRemoteURLComponents.url else { return false }
        return GitRepository(remoteURL: plainRemoteURL, storeDirectory: model.store.gitRepositoriesDir).isCloned
    }

    private var filteredRepositories: [GitHubAPIClient.Repository] {
        guard !repositorySearch.isEmpty else { return repositories }
        return repositories.filter { $0.fullName.localizedCaseInsensitiveContains(repositorySearch) }
    }
}

// MARK: - GitHub Loading

extension NewCodebaseSheet {

    func loadRepositories() async {
        guard let account else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            repositories = try await repositoryService.repositories(credential: account.credential)
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }

    func loadRefs(for repository: GitHubAPIClient.Repository) async {
        guard let account else { return }
        isLoadingRefs = true
        defer { isLoadingRefs = false }
        do {
            refs = try await repositoryService.refs(
                credential: account.credential, owner: repository.owner.login, repo: repository.name)
            selectedRef = refs.first { $0.kind == .branch && $0.name == repository.defaultBranch } ?? refs.first
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }
}
