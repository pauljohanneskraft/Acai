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

extension NewCodebaseSheetContent {
    @ViewBuilder
    var remoteURLSection: some View {
        Section {
            nameField(isOptional: true, identifier: "newCodebase.remoteNameField")
            TextField(text: $sheet.remoteAddress, prompt: Text(verbatim: "https://example.com/team/project.git")) {
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
            if sheet.isAlreadyCloned(RemoteAddress(text: sheet.remoteAddress).validURL) {
                alreadyClonedHint
            }
        } footer: {
            Text(.app("View.NewCodebaseSheet.RemoteAddressFooter"))
        }
    }

    @ViewBuilder
    private var remoteListingRow: some View {
        switch sheet.remoteListing {
        case .invalid(let problem):
            Label(problem.message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .accessibilityIdentifier("newCodebase.remoteAddressProblem")
        case .loaded(let remoteRefs):
            Picker(.app("View.NewCodebaseSheet.BranchTag"), selection: $sheet.selectedRemoteRef) {
                ForEach(remoteRefs) { ref in
                    Text(verbatim: ref.name).tag(Optional(ref))
                }
            }
            .accessibilityIdentifier("newCodebase.remoteRefPicker")
        case .failed:
            Button(.app("View.NewCodebaseSheet.Retry")) {
                Task { await sheet.listRemote() }
            }
            .accessibilityIdentifier("newCodebase.remoteRefs.retryButton")
        case .idle, .loading:
            EmptyView()
        }
        AsyncOperationStatusView(identifierPrefix: "newCodebase.remoteRefs", phase: sheet.remoteListing.phase)
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
