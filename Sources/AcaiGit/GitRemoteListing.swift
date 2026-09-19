import Foundation
import SwiftGitX
import libgit2

/// The branches and tags a remote advertises, read without cloning anything (`git ls-remote`).
/// `remoteURL` may carry credentials in its userinfo, like `GitClone`'s.
public struct GitRemoteListing {
    public let remoteURL: URL

    public struct Result: Hashable, Sendable {
        public let refs: [GitCheckout.Ref]
        /// The branch the remote's `HEAD` points at, when it advertises one.
        public let defaultBranch: String?

        public init(refs: [GitCheckout.Ref], defaultBranch: String?) {
            self.refs = refs
            self.defaultBranch = defaultBranch
        }
    }

    public init(remoteURL: URL) {
        self.remoteURL = remoteURL
    }

    public func list() async throws -> Result {
        try Task.checkCancellation()
        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw GitFailure(message: "Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var remotePointer: OpaquePointer?
        guard git_remote_create_detached(&remotePointer, remoteURL.absoluteString) == 0, let remotePointer else {
            throw GitFailure(message: lastErrorMessage("Couldn't read the remote address"))
        }
        defer { git_remote_free(remotePointer) }

        var callbacks = git_remote_callbacks()
        git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION))
        guard git_remote_connect(remotePointer, GIT_DIRECTION_FETCH, &callbacks, nil, nil) == 0 else {
            throw GitFailure(message: lastErrorMessage("Couldn't connect to the remote"))
        }
        defer { git_remote_disconnect(remotePointer) }
        try Task.checkCancellation()

        var heads: UnsafeMutablePointer<UnsafePointer<git_remote_head>?>?
        var count = 0
        guard git_remote_ls(&heads, &count, remotePointer) == 0 else {
            throw GitFailure(message: lastErrorMessage("Couldn't list the remote's branches"))
        }

        var branches: [String] = []
        var tags: [String] = []
        for index in 0..<count {
            guard let head = heads?[index], let name = head.pointee.name else { continue }
            let fullName = String(cString: name)
            if let branch = fullName.dropPrefix("refs/heads/") {
                branches.append(branch)
            } else if let tag = fullName.dropPrefix("refs/tags/"), !tag.hasSuffix("^{}") {
                tags.append(tag)
            }
        }

        let refs = branches.sorted().map { GitCheckout.Ref(name: $0, kind: .branch) }
            + tags.sorted().map { GitCheckout.Ref(name: $0, kind: .tag) }
        return Result(refs: refs, defaultBranch: defaultBranch(of: remotePointer))
    }

    private func defaultBranch(of remotePointer: OpaquePointer) -> String? {
        var buffer = git_buf()
        defer { git_buf_dispose(&buffer) }
        guard git_remote_default_branch(&buffer, remotePointer) == 0, let pointer = buffer.ptr else { return nil }
        return String(cString: pointer).dropPrefix("refs/heads/")
    }

    private func lastErrorMessage(_ context: String) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(context): \(String(cString: message))"
        }
        return context
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
