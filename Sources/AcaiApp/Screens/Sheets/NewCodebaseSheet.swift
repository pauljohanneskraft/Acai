import SwiftUI
import UniformTypeIdentifiers

struct NewCodebaseSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case localFolder = "Local Folder"
        case gitHub = "From GitHub"
        var id: String { rawValue }
    }

    let projectID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var source: Source = .localFolder
    @State private var name = ""

    // Local-folder state
    @State private var directoryURL: URL?
    @State private var securityScopedBookmark: SecurityScopedBookmark?
    @State private var isChoosingDirectory = false

    // GitHub state
    @State private var account = GitHubTokenStore().load()
    @State private var repositories: [GitHubAPIClient.Repository] = []
    @State private var repositorySearch = ""
    @State private var selectedRepository: GitHubAPIClient.Repository?
    @State private var refs: [GitHubRef] = []
    @State private var selectedRef: GitHubRef?
    @State private var isLoadingRepositories = false
    @State private var isLoadingRefs = false
    @State private var isCloning = false
    @State private var gitHubErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch source {
                case .localFolder:
                    localFolderSection
                case .gitHub:
                    gitHubSection
                }
            }
            #if os(macOS)
            .frame(maxWidth: 480)
            #endif
            .navigationTitle("Add Codebase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
            .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
                guard let url = try? result.get() else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                directoryURL = url
                securityScopedBookmark = try? SecurityScopedBookmark(resolving: url)
            }
            .onChange(of: account) { _, newValue in
                if newValue != nil { Task { await loadRepositories() } }
            }
            .onChange(of: selectedRepository) { _, newValue in
                if let newValue { Task { await loadRefs(for: newValue) } }
            }
        }
    }

    private var localFolderSection: some View {
        Section {
            TextField("Name", text: $name)
            LabeledContent("Directory") {
                Text(directoryURL?.path ?? "No directory chosen")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(directoryURL == nil ? .secondary : .primary)
            }
            Button("Choose…") { isChoosingDirectory = true }
        }
    }

    @ViewBuilder
    private var gitHubSection: some View {
        Section {
            GitHubAccountSection(account: $account)
        }
        if account != nil {
            Section {
                TextField("Name (optional)", text: $name)
                TextField("Search repositories", text: $repositorySearch)
                if isLoadingRepositories {
                    ProgressView()
                } else {
                    Picker("Repository", selection: $selectedRepository) {
                        Text("None").tag(GitHubAPIClient.Repository?.none)
                        ForEach(filteredRepositories) { repository in
                            Text(repository.fullName).tag(Optional(repository))
                        }
                    }
                }
                if selectedRepository != nil {
                    if isLoadingRefs {
                        ProgressView()
                    } else {
                        Picker("Branch/Tag", selection: $selectedRef) {
                            ForEach(refs) { ref in
                                Text(ref.name).tag(Optional(ref))
                            }
                        }
                    }
                }
            }
        }
        if let gitHubErrorMessage {
            Section {
                Text(gitHubErrorMessage).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch source {
        case .localFolder:
            Button("Add") {
                if let dir = directoryURL {
                    model.editing.addCodebase(
                        to: projectID, name: name, directoryURL: dir,
                        securityScopedBookmark: securityScopedBookmark)
                }
                dismiss()
            }.disabled(name.isEmpty || directoryURL == nil)
        case .gitHub:
            Button("Clone") {
                guard let repository = selectedRepository, let ref = selectedRef, let account, !isCloning else {
                    return
                }
                isCloning = true
                Task {
                    await model.editing.addGitHubCodebase(
                        to: projectID,
                        name: name.isEmpty ? repository.name : name,
                        credential: account.credential,
                        target: GitHubRepositoryRef(
                            owner: repository.owner.login, repo: repository.name, ref: ref.name, kind: ref.kind)
                    )
                    isCloning = false
                    dismiss()
                }
            }.disabled(selectedRepository == nil || selectedRef == nil || account == nil || isCloning)
        }
    }

    private var filteredRepositories: [GitHubAPIClient.Repository] {
        guard !repositorySearch.isEmpty else { return repositories }
        return repositories.filter { $0.fullName.localizedCaseInsensitiveContains(repositorySearch) }
    }

    private func loadRepositories() async {
        guard let account else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            let client = GitHubAPIClient(credential: account.credential)
            var allRepositories: [GitHubAPIClient.Repository] = []
            var page = 1
            while true {
                let batch = try await client.repositories(page: page)
                allRepositories += batch
                guard batch.count == GitHubAPIClient.repositoriesPerPage else { break }
                page += 1
            }
            repositories = allRepositories
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }

    private func loadRefs(for repository: GitHubAPIClient.Repository) async {
        guard let account else { return }
        isLoadingRefs = true
        defer { isLoadingRefs = false }
        do {
            let client = GitHubAPIClient(credential: account.credential)
            async let branches = client.branches(owner: repository.owner.login, repo: repository.name)
            async let tags = client.tags(owner: repository.owner.login, repo: repository.name)
            refs = try await branches + tags
            selectedRef = refs.first { $0.kind == .branch && $0.name == repository.defaultBranch } ?? refs.first
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }
}
