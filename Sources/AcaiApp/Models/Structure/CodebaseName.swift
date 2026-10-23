import Foundation

/// A remote's own name: the last component of its address, without the `.git` a clone URL carries.
/// An address with no path of its own falls back to its host.
struct RemoteRepositoryName {
    let remoteURL: URL

    var value: String {
        let last = remoteURL.lastPathComponent
        let name = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
        guard !name.isEmpty, name != "/" else { return remoteURL.host() ?? "" }
        return name
    }
}

/// A local folder's name, picked or dropped alike: the remote it already points at, else its own.
struct LocalFolderCodebaseName {
    let folderURL: URL
    let repository: CodebaseRepositoryReference?

    var value: String {
        if let repository {
            let name = RemoteRepositoryName(remoteURL: repository.remoteURL).value
            if !name.isEmpty { return name }
        }
        return folderURL.lastPathComponent
    }
}

/// A name no other codebase in the same project already uses, numbering the ones that repeat — two
/// worktrees of the same repository, or two folders sharing a last path component. Names come from
/// what a codebase is rather than from the user, so a repeat is expected rather than an error.
struct UniqueCodebaseName {
    let proposed: String
    let taken: [String]

    var value: String {
        guard taken.contains(proposed) else { return proposed }
        var suffix = 2
        while taken.contains("\(proposed) \(suffix)") { suffix += 1 }
        return "\(proposed) \(suffix)"
    }
}
