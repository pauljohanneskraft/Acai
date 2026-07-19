import SwiftUI

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

    private let tokenStore = GitHubTokenStore()

    var body: some View {
        if let account {
            signedInView(account)
        } else {
            signedOutView
        }
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
                Button("Sign in with GitHub") { Task { await startDeviceFlow() } }
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
            Link("Open \(code.verificationURI.host ?? "github.com")", destination: code.verificationURI)
            ProgressView()
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
            let credential = try await flow.pollForCredential(code)
            deviceCode = nil
            signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
            deviceCode = nil
        }
    }
}
