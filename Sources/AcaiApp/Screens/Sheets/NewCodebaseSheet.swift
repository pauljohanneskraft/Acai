import AcaiGit
import SwiftUI
import UniformTypeIdentifiers

struct NewCodebaseSheet: View {
    let projectID: UUID
    let remoteService: GitRemoteService
    let hostingService: GitHubHostingService
    let sizePolicy: CloneSizePolicy
    @EnvironmentObject private var model: ProjectBrowserViewModel

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

    var body: some View {
        NewCodebaseSheetContent(sheet: NewCodebaseSheetModel(
            projectID: projectID, editor: model.editing, hubStoreDirectory: model.store.gitRepositoriesDir,
            remoteService: remoteService, hostingService: hostingService, sizePolicy: sizePolicy))
    }
}

struct NewCodebaseSheetContent: View {
    @StateObject var sheet: NewCodebaseSheetModel
    @EnvironmentObject var model: ProjectBrowserViewModel
    // Reads signed-in state from the shared store, so signing in/out in Settings is reflected
    // here immediately — see `gitHubSection` for the signed-out prompt.
    @EnvironmentObject private var accountStore: GitHubAccountStore
    @EnvironmentObject private var settingsPresenter: SettingsPresenter
    @Environment(\.dismiss) var dismiss
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    init(sheet: @autoclosure @escaping () -> NewCodebaseSheetModel) {
        _sheet = StateObject(wrappedValue: sheet())
    }

    @FocusState private var isNameFieldFocused: Bool
    @State var isChoosingDirectory = false
    @State private var repositorySearch = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(.app("View.NewCodebaseSheet.Source"), selection: $sheet.source) {
                    ForEach(NewCodebaseSheetModel.Source.allCases) { source in
                        Text(localized: source.title)
                            .tag(source)
                            .accessibilityIdentifier("newCodebase.source.\(source.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("newCodebase.sourcePicker")

                switch sheet.source {
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
            .onDisappear { sheet.cancelPendingWork() }
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
            .onChange(of: accountStore.account) { _, account in sheet.account = account }
            .task(id: accountStore.account?.login) {
                sheet.account = accountStore.account
                await sheet.loadRepositories()
            }
        }
        // On the stack rather than on the `Form`: the Form hosts the repository and ref menus, and a
        // dialog asked for while one of them is still dismissing is dropped — leaving the binding
        // true, so no later tap can present it either and Clone stays dead for good.
        .confirmationDialog(
            largeCloneTitle, isPresented: Binding(
                get: { sheet.pendingLargeClone != nil }, set: { if !$0 { sheet.pendingLargeClone = nil } }),
            titleVisibility: .visible, presenting: sheet.pendingLargeClone
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

    private var largeCloneTitle: Text {
        let size = Int64(sheet.pendingLargeClone?.sizeKilobytes ?? 0) * 1024
        return Text(.app("View.NewCodebaseSheet.LargeCloneTitle \(size.formatted(.byteCount(style: .file)))"))
    }

    private func clone(_ pending: PendingClone, depth: GitHistoryDepth) {
        Task {
            await sheet.clone(pending, depth: depth)
            dismiss()
        }
    }

    /// Not a bare `TextField(text:label:)` on macOS: inside a `Form` its title renders as an extra
    /// leading label rather than a placeholder, misaligning it against `LabeledContent` rows.
    /// An optional name falls back to the repository's own.
    @ViewBuilder
    func nameField(isOptional: Bool, identifier: String) -> some View {
        #if os(macOS)
        LabeledContent {
            TextField("", text: $sheet.name, prompt: Text(localized: isOptional
                ? .app("View.NewCodebaseSheet.Optional") : .app("View.NewCodebaseSheet.EGMyLibrary")))
                .multilineTextAlignment(.trailing)
                .focused($isNameFieldFocused)
                .accessibilityIdentifier(identifier)
        } label: {
            Text(.app("View.NewCodebaseSheet.Name"))
        }
        #else
        TextField(text: $sheet.name) {
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
            if let account = sheet.account {
                // Read-only summary — the full sign-in UI lives in Settings.
                HStack {
                    Text(.app("View.NewCodebaseSheet.Signed \(account.login)"))
                        .accessibilityIdentifier("newCodebase.signedInAsLabel")
                    Spacer()
                    settingsLinkButton
                }
            } else {
                VStack(alignment: .leading, spacing: .spacingS) {
                    Text(.app("View.NewCodebaseSheet.SignGitHubSettings"))
                        .foregroundStyle(.secondary)
                    settingsLinkButton
                }
            }
        }
        if sheet.account != nil {
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
                if sheet.isLoadingRepositories {
                    ProgressView()
                } else {
                    Picker(.app("View.NewCodebaseSheet.Repository"), selection: $sheet.selectedRepository) {
                        Text(.app("View.NewCodebaseSheet.None")).tag(GitHubAPIClient.Repository?.none)
                        ForEach(filteredRepositories) { repository in
                            Text(verbatim: repository.fullName).tag(Optional(repository))
                        }
                    }
                    .accessibilityIdentifier("newCodebase.repositoryPicker")
                }
                if sheet.selectedRepository != nil {
                    if sheet.isLoadingRefs {
                        ProgressView()
                    } else {
                        Picker(.app("View.NewCodebaseSheet.BranchTag"), selection: $sheet.selectedRef) {
                            ForEach(sheet.refs) { ref in
                                Text(verbatim: ref.name).tag(Optional(ref))
                            }
                        }
                        .accessibilityIdentifier("newCodebase.refPicker")
                    }
                }
                if sheet.isAlreadyCloned(sheet.selectedRepository.flatMap(sheet.gitHubRemoteURL)) {
                    alreadyClonedHint
                }
            }
        }
        if let gitHubErrorMessage = sheet.gitHubErrorMessage {
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
        switch sheet.source {
        case .localFolder:
            Button(.app("View.NewCodebaseSheet.Add")) {
                sheet.addLocalFolder()
                dismiss()
            }
            .disabled(sheet.name.isEmpty || sheet.directoryURL == nil)
            .accessibilityIdentifier("newCodebase.addButton")
        case .remoteURL, .gitHub:
            let pending = sheet.pendingClone
            Button(sheet.isAlreadyCloned(pending?.remoteURL)
                ? .app("View.NewCodebaseSheet.Add")
                : .app("View.NewCodebaseSheet.Clone")) {
                guard let pending, !sheet.clonePhase.isInFlight else { return }
                Task {
                    if await sheet.requestClone(pending) { dismiss() }
                }
            }
            .disabled(pending == nil || sheet.clonePhase.isInFlight)
            .accessibilityIdentifier("newCodebase.cloneButton")
            AsyncOperationStatusView(identifierPrefix: "newCodebase.clone", phase: sheet.clonePhase)
        }
    }

    private var filteredRepositories: [GitHubAPIClient.Repository] {
        guard !repositorySearch.isEmpty else { return sheet.repositories }
        return sheet.repositories.filter { $0.fullName.localizedCaseInsensitiveContains(repositorySearch) }
    }
}
