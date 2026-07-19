import SwiftUI
#if os(iOS)
import SafariServices
import UIKit
#else
import AppKit
#endif

/// Sign-in/out UI for the app's single GitHub account — shared by `NewCodebaseSheet`'s GitHub tab
/// (the only place it's embedded today). Two sign-in paths: paste a fine-grained PAT, or a GitHub
/// App device-flow sign-in (only offered once `GitHubAppConfiguration.standard.clientID` has
/// actually been filled in — see that type's doc comment for the one-time setup it depends on).
struct GitHubAccountSection: View {
    @Binding var account: GitHubTokenStore.StoredAccount?

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

    private let tokenStore = GitHubTokenStore()

    var body: some View {
        Group {
            if let account {
                signedInView(account)
            } else {
                signedOutView
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private func signedInView(_ account: GitHubTokenStore.StoredAccount) -> some View {
        HStack {
            Text("Signed in as \(account.login)")
            Spacer()
            Button("Sign Out") {
                tokenStore.clear()
                self.account = nil
            }
        }
    }

    @ViewBuilder
    private var signedOutView: some View {
        if let deviceCode {
            deviceCodeView(deviceCode)
        } else {
            Text("Paste a fine-grained personal access token scoped to Contents: Read-only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Personal Access Token", text: $patText)
            Button("Sign In with Token") { signIn(with: .personalAccessToken(patText)) }
                .disabled(patText.isEmpty || isSigningIn)

            if !GitHubAppConfiguration.standard.clientID.isEmpty {
                Button("Sign in with GitHub") { pollTask = Task { await startDeviceFlow() } }
                    .disabled(isSigningIn)
            }
        }
        if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
        }
    }

    private func deviceCodeView(_ code: GitHubDeviceAuthFlow.DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter this code at the link below:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(code.userCode)
                .font(.title2.monospaced().bold())
            Text("Copied to clipboard")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #if os(iOS)
            // An in-app sheet instead of `Link` (external Safari) so Acai stays foregrounded —
            // and the poll above keeps running uninterrupted — for the whole time the user is
            // authorizing on github.com. No callback URL is needed: the credential still comes
            // from `pollForCredential` below, not from anything this page redirects to.
            Button("Open \(code.verificationURI.host ?? "github.com")") {
                isPresentingVerificationPage = true
            }
            .sheet(isPresented: $isPresentingVerificationPage) {
                SafariView(url: code.verificationURI)
            }
            #else
            Link("Open \(code.verificationURI.host ?? "github.com")", destination: code.verificationURI)
            #endif
            HStack {
                ProgressView()
                Spacer()
                Button("Cancel", role: .cancel) {
                    pollTask?.cancel()
                    pollTask = nil
                    deviceCode = nil
                }
            }
        }
    }

    private func signIn(with credential: GitHubCredential) {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                let user = try await GitHubAPIClient(credential: credential).authenticatedUser()
                let stored = GitHubTokenStore.StoredAccount(
                    credential: credential, login: user.login, avatarURL: user.avatarURL)
                try tokenStore.save(stored)
                account = stored
                patText = ""
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startDeviceFlow() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let flow = GitHubDeviceAuthFlow(clientID: GitHubAppConfiguration.standard.clientID)
            let code = try await flow.requestDeviceCode()
            deviceCode = code
            copyToClipboard(code.userCode)
            let credential = try await flow.pollForCredential(code)
            deviceCode = nil
            signIn(with: credential)
        } catch {
            // A cancellation means the user already dismissed this via "Cancel" (which cleared
            // `deviceCode` itself) or by leaving the sheet — surfacing an error here would show a
            // spurious "cancelled" message after the user's own deliberate action.
            guard !Task.isCancelled else { return }
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
/// Wraps `SFSafariViewController` so the device-flow verification page opens in-app rather than
/// backgrounding Acai in external Safari — see `deviceCodeView`'s comment for why that matters.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
