import AcaiGit
import SwiftUI

/// The Remote URL source's branch list, read from the remote without cloning it.
enum RemoteListingState: Equatable {
    case idle
    case invalid(RemoteAddress.Problem)
    case loading
    case loaded([GitCheckout.Ref])
    case failed(String)

    var phase: AsyncOperationPhase {
        switch self {
        case .idle, .invalid:
            .idle
        case .loading:
            .loading(.app("View.NewCodebaseSheet.ReadingBranches"))
        case .loaded:
            .loaded
        case .failed(let message):
            .failed(message)
        }
    }
}

extension NewCodebaseSheet {

    // MARK: - Remote URL

    @ViewBuilder
    var remoteURLSection: some View {
        Section {
            nameField(isOptional: true, identifier: "newCodebase.remoteNameField")
            TextField(text: $remoteAddress, prompt: Text(verbatim: "https://example.com/team/project.git")) {
                Text(.app("View.NewCodebaseSheet.RemoteAddress"))
            }
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .accessibilityIdentifier("newCodebase.remoteAddressField")
            remoteListingRow
            if isAlreadyCloned(RemoteAddress(text: remoteAddress).validURL) {
                alreadyClonedHint
            }
        } footer: {
            Text(.app("View.NewCodebaseSheet.RemoteAddressFooter"))
        }
    }

    @ViewBuilder
    private var remoteListingRow: some View {
        switch remoteListing {
        case .invalid(let problem):
            Label(problem.message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .accessibilityIdentifier("newCodebase.remoteAddressProblem")
        case .loaded(let remoteRefs):
            Picker(.app("View.NewCodebaseSheet.BranchTag"), selection: $selectedRemoteRef) {
                ForEach(remoteRefs) { ref in
                    Text(verbatim: ref.name).tag(Optional(ref))
                }
            }
            .accessibilityIdentifier("newCodebase.remoteRefPicker")
        case .failed:
            Button(.app("View.NewCodebaseSheet.Retry")) {
                Task { await listRemote() }
            }
            .accessibilityIdentifier("newCodebase.remoteRefs.retryButton")
        case .idle, .loading:
            EmptyView()
        }
        AsyncOperationStatusView(identifierPrefix: "newCodebase.remoteRefs", phase: remoteListing.phase)
    }

    /// Waits for typing to pause before contacting the remote; a new keystroke cancels this task.
    func listRemoteDebounced() async {
        selectedRemoteRef = nil
        guard !remoteAddress.isEmpty else {
            remoteListing = .idle
            return
        }
        if case .failure(let problem) = RemoteAddress(text: remoteAddress).result {
            remoteListing = .invalid(problem)
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }
        await listRemote()
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

    /// The credential-free URL `CodebaseRepositoryReference.remoteURL` ends up storing.
    func gitHubRemoteURL(_ repository: GitHubAPIClient.Repository) -> URL? {
        guard let account else { return nil }
        return GitHubRemote(credential: account.credential, owner: repository.owner.login, repo: repository.name)
            .plainURL
    }

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

    func loadRefs(for repository: GitHubAPIClient.Repository) async {
        guard let remoteURL = gitHubRemoteURL(repository) else { return }
        isLoadingRefs = true
        defer { isLoadingRefs = false }
        do {
            refs = try await remoteService.listRemote(RemoteEndpoint(remoteURL: remoteURL)).refs
            selectedRef = refs.first { $0.kind == .branch && $0.name == repository.defaultBranch } ?? refs.first
        } catch {
            gitHubErrorMessage = error.localizedDescription
        }
    }
}

extension RemoteAddress {
    var validURL: URL? {
        if case .success(let url) = result { return url }
        return nil
    }
}

extension RemoteAddress.Problem {
    var message: LocalizedStringResource {
        switch self {
        case .empty, .malformed:
            .app("RemoteAddress.Problem.Malformed")
        case .unsupportedScheme:
            .app("RemoteAddress.Problem.UnsupportedScheme")
        case .containsCredentials:
            .app("RemoteAddress.Problem.ContainsCredentials")
        }
    }
}
