import AcaiGit
import SwiftUI
import UniformTypeIdentifiers

struct NewCodebaseSheet: View {
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
    let remoteService: GitRemoteService
    let hostingService: GitHubHostingService
    let sizePolicy: CloneSizePolicy
    @EnvironmentObject var model: ProjectBrowserViewModel
    // Reads signed-in state from the shared store, so signing in/out in Settings is reflected
    // here immediately — see `gitHubSection` for the signed-out prompt.
    @EnvironmentObject var accountStore: GitHubAccountStore
    @EnvironmentObject private var settingsPresenter: SettingsPresenter
    @Environment(\.dismiss) var dismiss
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    /// Defaults to real git and the real GitHub API, swapped for fixtures under a UI test.
    init(
        projectID: UUID, remoteService: GitRemoteService? = nil, hostingService: GitHubHostingService? = nil,
        sizePolicy: CloneSizePolicy = .standard
    ) {
        self.projectID = projectID
        self.remoteService = remoteService ?? GitRemoteServiceResolver().resolve()
        self.hostingService = hostingService ?? GitHubHostingServiceResolver().resolve()
        self.sizePolicy = sizePolicy
    }

    @State var source: Source = .localFolder
    @State var name = ""
    @FocusState private var isNameFieldFocused: Bool

    @State var directoryURL: URL?
    @State var securityScopedBookmark: SecurityScopedBookmark?
    @State var isChoosingDirectory = false
    /// Set when the picked folder turns out to already be a git working directory with an
    /// `origin` remote. `nil` for a plain folder.
    @State var repositoryReference: CodebaseRepositoryReference?

    @State var remoteAddress = ""
    @State var remoteListing: RemoteListingState = .idle
    @State var selectedRemoteRef: GitCheckout.Ref?

    @State var repositories: [GitHubAPIClient.Repository] = []
    @State private var repositorySearch = ""
    @State var selectedRepository: GitHubAPIClient.Repository?
    @State var refs: [GitCheckout.Ref] = []
    @State var selectedRef: GitCheckout.Ref?
    @State var isLoadingRepositories = false
    @State var isLoadingRefs = false
    @State var clonePhase: AsyncOperationPhase = .idle
    @State var gitHubErrorMessage: String?
    @State var pendingLargeClone: PendingClone?

    var account: GitHubTokenStore.StoredAccount? { accountStore.account }

    var body: some View {
        NavigationStack {
            Form {
                Picker(.app("View.NewCodebaseSheet.Source"), selection: $source) {
                    ForEach(Source.allCases) { source in
                        Text(localized: source.title)
                            .tag(source)
                            .accessibilityIdentifier("newCodebase.source.\(source.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("newCodebase.sourcePicker")

                switch source {
                case .localFolder:
                    localFolderSection
                case .remoteURL:
                    remoteURLSection
                case .gitHub:
                    gitHubSection
                }
            }
            #if os(macOS)
            // `.grouped` gives this sheet's multiple sections the separated, padded look a lone
            // `Section` gets for free.
            .formStyle(.grouped)
            .frame(maxWidth: 480)
            #else
            // A single `.large` detent: the GitHub tab is taller than `.medium` fits, and starting
            // collapsed left its pickers absent from the accessibility tree below the fold.
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
                pickDirectory(url)
            }
            // `.task(id:)`, not `.onChange(of:)`: `account` is typically already non-nil the first
            // time this sheet appears, which `.onChange` would never see.
            .task(id: account?.login) {
                guard account != nil else { return }
                await loadRepositories()
            }
            .onChange(of: selectedRepository) { _, newValue in
                if let newValue { Task { await loadRefs(for: newValue) } }
            }
            .task(id: remoteAddress) {
                await listRemoteDebounced()
            }
            .confirmationDialog(
                largeCloneTitle, isPresented: Binding(
                    get: { pendingLargeClone != nil }, set: { if !$0 { pendingLargeClone = nil } }),
                titleVisibility: .visible, presenting: pendingLargeClone
            ) { pending in
                Button(.app("View.NewCodebaseSheet.CloneLatestSnapshot")) {
                    clone(pending, depth: .latestSnapshot)
                }
                .accessibilityIdentifier("newCodebase.largeClone.latestSnapshotButton")
                Button(.app("View.NewCodebaseSheet.CloneFullHistory")) {
                    clone(pending, depth: .full)
                }
                .accessibilityIdentifier("newCodebase.largeClone.fullHistoryButton")
                Button(.app("View.NewCodebaseSheet.Cancel"), role: .cancel) {}
            } message: { _ in
                Text(.app("View.NewCodebaseSheet.LargeCloneMessage"))
            }
        }
    }

    private var largeCloneTitle: Text {
        let size = Int64(pendingLargeClone?.sizeKilobytes ?? 0) * 1024
        return Text(.app("View.NewCodebaseSheet.LargeCloneTitle \(size.formatted(.byteCount(style: .file)))"))
    }

    /// Not a bare `TextField(text:label:)` on macOS: inside a `Form` its title renders as an extra
    /// leading label rather than a placeholder, misaligning it against `LabeledContent` rows.
    /// An optional name falls back to the repository's own.
    @ViewBuilder
    func nameField(isOptional: Bool, identifier: String) -> some View {
        #if os(macOS)
        LabeledContent {
            TextField("", text: $name, prompt: Text(localized: isOptional
                ? .app("View.NewCodebaseSheet.Optional") : .app("View.NewCodebaseSheet.EGMyLibrary")))
                .multilineTextAlignment(.trailing)
                .focused($isNameFieldFocused)
                .accessibilityIdentifier(identifier)
        } label: {
            Text(.app("View.NewCodebaseSheet.Name"))
        }
        #else
        TextField(text: $name) {
            Text(localized: isOptional
                ? .app("View.NewCodebaseSheet.NameOptional") : .app("View.NewCodebaseSheet.Name"))
        }
        .focused($isNameFieldFocused)
        .accessibilityIdentifier(identifier)
        #endif
    }

    @ViewBuilder
    private var gitHubSection: some View {
        Section {
            if let account {
                // Read-only summary — the full sign-in UI lives in Settings.
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
                nameField(isOptional: true, identifier: "newCodebase.nameField")
                #if os(macOS)
                LabeledContent {
                    TextField(
                        "", text: $repositorySearch, prompt: Text(.app("View.NewCodebaseSheet.SearchRepositories"))
                    )
                    .multilineTextAlignment(.trailing)
                } label: {
                    Text(.app("View.NewCodebaseSheet.Search"))
                }
                #else
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
                // Adding attaches a new worktree to the existing shared clone instead of cloning.
                if isAlreadyCloned(selectedRepository.flatMap(gitHubRemoteURL)) {
                    alreadyClonedHint
                }
            }
        }
        if let gitHubErrorMessage {
            Section {
                Text(verbatim: gitHubErrorMessage).foregroundStyle(.red)
            }
        }
    }

    var alreadyClonedHint: some View {
        Label(.app("View.NewCodebaseSheet.AlreadyClonedLocally"), systemImage: "checkmark.icloud")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("newCodebase.alreadyClonedHint")
    }

    /// macOS opens the `Settings` scene; iPad/iPhone dismiss this sheet and present the Settings
    /// sheet instead, since a sheet can't stack cleanly on another sheet there.
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
        case .remoteURL, .gitHub:
            let pending = pendingClone
            Button(isAlreadyCloned(pending?.remoteURL)
                ? .app("View.NewCodebaseSheet.Add")
                : .app("View.NewCodebaseSheet.Clone")) {
                guard let pending, !clonePhase.isInFlight else { return }
                requestClone(pending)
            }
            .disabled(pending == nil || clonePhase.isInFlight)
            .accessibilityIdentifier("newCodebase.cloneButton")
            AsyncOperationStatusView(identifierPrefix: "newCodebase.clone", phase: clonePhase)
        }
    }

    private var filteredRepositories: [GitHubAPIClient.Repository] {
        guard !repositorySearch.isEmpty else { return repositories }
        return repositories.filter { $0.fullName.localizedCaseInsensitiveContains(repositorySearch) }
    }
}
