import SwiftUI
#if os(iOS)
import SafariServices
import UIKit
#else
import AppKit
#endif

/// Sign-in/out UI for the app's single GitHub account — the Settings pane's content, reachable
/// via ⌘, on macOS or the sidebar's gear icon on iPad/iPhone. `NewCodebaseSheet`'s GitHub tab
/// reads `GitHubAccountStore` and points here when signed out. Two sign-in paths: paste a
/// fine-grained PAT, or a GitHub App device-flow sign-in (only offered once
/// `GitHubAppConfiguration.standard.clientID` has actually been filled in — see that type's doc
/// comment for the one-time setup it depends on).
struct GitHubAccountSection: View {
    @EnvironmentObject private var accountStore: GitHubAccountStore

    @State private var patText = ""
    @State private var isSigningIn = false
    @State private var deviceCode: GitHubDeviceAuthFlow.DeviceCode?
    @State private var errorMessage: String?
    /// Owns the in-flight device-flow poll so it can be cancelled from the "Cancel" button or when
    /// this view disappears (e.g. the host sheet is dismissed) — without this, the poll would keep
    /// running for up to the code's ~15 minute lifetime and could still sign the user in after
    /// they'd already backed out.
    @State private var pollTask: Task<Void, Never>?
    #if os(iOS)
    @State private var isPresentingVerificationPage = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let account = accountStore.account {
                signedInView(account)
            } else {
                signedOutView
            }
        }
        .onDisappear { pollTask?.cancel() }
        .task(id: accountStore.account?.login) {
            guard accountStore.account != nil else { return }
            accountStore.refreshCodebaseCount()
        }
        #if os(iOS)
        // Attaching the sheet to a background view hides the presentation anchor from the root of
        // the hierarchy, avoiding conflicts with the host sheet already presented.
        .background {
            Color.clear
                .sheet(isPresented: $isPresentingVerificationPage) {
                    if let url = deviceCode?.verificationURI {
                        SafariView(url: url)
                    } else {
                        // Shown during the dismissal animation after deviceCode is set to nil
                        VStack(spacing: 16) {
                            ProgressView()
                            Text(.app("View.GitHubAccountSection.CompletingSign"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
        }
        #endif
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedInView(_ account: GitHubTokenStore.StoredAccount) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: account.avatarURL) { image in
                image.resizable()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.login)
                    .font(.headline)
                    .accessibilityIdentifier("github.signedInRow")
                Text(localized: codebaseCountLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("github.usedByCodebasesLabel")
            }
            Spacer()
            Button(.app("View.GitHubAccountSection.SignOut"), role: .destructive) {
                accountStore.signOut()
            }
            .accessibilityIdentifier("github.signOutButton")
        }

        if let expiryMessage {
            Label(expiryMessage, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("github.expiryWarning")
        }

        scopeChecklist(account)

        HStack {
            if accountStore.isRefreshingScopes {
                ProgressView().controlSize(.small)
            }
            Button(.app("View.GitHubAccountSection.RefreshScopes")) {
                Task { await accountStore.refreshScopes() }
            }
            .buttonStyle(.borderless)
            .disabled(accountStore.isRefreshingScopes)
            .accessibilityIdentifier("github.refreshScopesButton")
        }
    }

    /// A checklist of which scopes the current token actually has. `nil` scopes (fine-grained
    /// PATs, which don't currently report this) show as "Unknown," never silently as "has every
    /// scope" or "has none."
    private func scopeChecklist(_ account: GitHubTokenStore.StoredAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.app("View.GitHubAccountSection.Scopes")).font(.caption).foregroundStyle(.secondary)
            if let scopes = account.scopes {
                ForEach([GitHubScope.contentsRead, .metadataRead, .pullRequestsRead], id: \.rawValue) { scope in
                    let has = scopes.contains(scope.rawValue)
                    Label(scope.displayName, systemImage: has ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(has ? .green : .secondary)
                        .font(.caption)
                }
            } else {
                Label(.app("View.GitHubAccountSection.UnknownTokenTypeDoesn"), systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("github.scopesUnknownLabel")
            }
        }
        .accessibilityIdentifier("github.scopeChecklist")
    }

    private var codebaseCountLine: LocalizedStringResource {
        .app("View.GitHubAccountSection.UsedByCodebases \(accountStore.codebaseCount)")
    }

    private var expiryMessage: LocalizedStringResource? {
        guard let expiresAt = accountStore.account?.tokenExpiresAt else { return nil }
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        guard daysRemaining <= 7 else { return nil }
        guard daysRemaining > 0 else { return .app("View.GitHubAccountSection.TokenExpired") }
        let when = expiresAt.formatted(.relative(presentation: .named))
        return .app("View.GitHubAccountSection.TokenExpires \(when)")
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutView: some View {
        if let deviceCode {
            deviceCodeView(deviceCode)
        } else {
            Text(.app("View.GitHubAccountSection.PasteFineGrainedPersonal"))
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(text: $patText) {
                Text(.app("View.GitHubAccountSection.PersonalAccessToken"))
            }
            .accessibilityIdentifier("github.patField")
            Button(.app("View.GitHubAccountSection.SignToken")) { signIn(with: .personalAccessToken(patText)) }
                .buttonStyle(.borderless)
                .disabled(patText.isEmpty || isSigningIn)
                .accessibilityIdentifier("github.signInWithTokenButton")

            if !GitHubAppConfiguration.standard.clientID.isEmpty {
                Text(.app("View.GitHubAccountSection.WeLlGenerateShort"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(.app("View.GitHubAccountSection.SignGitHub")) { pollTask = Task { await startDeviceFlow() } }
                    .buttonStyle(.borderless)
                    .disabled(isSigningIn)
                    .accessibilityIdentifier("github.signInWithDeviceFlowButton")
            }
        }
        if let errorMessage {
            Text(verbatim: errorMessage).font(.caption).foregroundStyle(.red)
        }
    }

    private func deviceCodeView(_ code: GitHubDeviceAuthFlow.DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("View.GitHubAccountSection.EnterCodeLinkBelow"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: code.userCode)
                .font(.title2.monospaced().bold())
            Text(.app("View.GitHubAccountSection.CopiedClipboard"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #if os(iOS)
            // An in-app sheet instead of `Link` (external Safari) so Acai stays foregrounded —
            // and the poll above keeps running uninterrupted — for the whole time the user is
            // authorizing on github.com. No callback URL is needed: the credential still comes
            // from `pollForCredential` below, not from anything this page redirects to.
            Button(.app("View.GitHubAccountSection.Open \(code.verificationURI.host ?? "github.com")")) {
                isPresentingVerificationPage = true
            }
            .buttonStyle(.borderless)
            #else
            Link(
                .app("View.GitHubAccountSection.Open \(code.verificationURI.host ?? "github.com")"),
                destination: code.verificationURI
            )
            #endif
            HStack {
                ProgressView()
                Spacer()
                Button(.app("View.GitHubAccountSection.Cancel"), role: .cancel) {
                    pollTask?.cancel()
                    pollTask = nil
                    deviceCode = nil
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func signIn(with credential: GitHubCredential) {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await accountStore.signIn(with: credential)
                patText = ""
                errorMessage = nil
                accountStore.refreshCodebaseCount()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startDeviceFlow() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let clientID = GitHubAppConfiguration.standard.clientID
            let code = try await accountStore.requestDeviceCode(clientID: clientID)
            deviceCode = code
            copyToClipboard(code.userCode)
            let credential = try await accountStore.pollForCredential(code, clientID: clientID)
            // The poll can succeed at almost the same moment the user taps "Cancel" — check
            // cancellation here too (not just in `catch` below), so a credential that arrives
            // right on that boundary doesn't still get signed in and written to Keychain.
            guard !Task.isCancelled else { return }

            #if os(iOS)
            isPresentingVerificationPage = false
            #endif
            deviceCode = nil
            signIn(with: credential)
        } catch {
            // A cancellation means the user already dismissed this via "Cancel" (which cleared
            // `deviceCode` itself) or by leaving the sheet — surfacing an error here would show a
            // spurious "cancelled" message after the user's own deliberate action.
            guard !Task.isCancelled else { return }

            #if os(iOS)
            isPresentingVerificationPage = false
            #endif
            errorMessage = error.localizedDescription
            deviceCode = nil
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

#if os(iOS)
/// Opens the device-flow verification page in-app rather than backgrounding Acai in external
/// Safari — see `deviceCodeView`'s comment for why that matters.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
