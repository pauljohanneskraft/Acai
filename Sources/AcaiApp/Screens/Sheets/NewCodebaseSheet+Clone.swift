import AcaiGit
import SwiftUI

struct PendingClone: Equatable {
    var name: String
    var remoteURL: URL
    var ref: GitCheckout.Ref
    var sizeKilobytes: Int?
}

extension NewCodebaseSheet {
    /// What Clone would add, or `nil` while the chosen source isn't complete.
    var pendingClone: PendingClone? {
        switch source {
        case .localFolder:
            return nil
        case .remoteURL:
            guard case .success(let remoteURL) = RemoteAddress(text: remoteAddress).result,
                  let ref = selectedRemoteRef
            else { return nil }
            let fallbackName = remoteURL.deletingPathExtension().lastPathComponent
            return PendingClone(
                name: name.isEmpty ? fallbackName : name, remoteURL: remoteURL, ref: ref, sizeKilobytes: nil)
        case .gitHub:
            guard let repository = selectedRepository, let ref = selectedRef, account != nil,
                  let remoteURL = gitHubRemoteURL(repository)
            else { return nil }
            return PendingClone(
                name: name.isEmpty ? repository.name : name, remoteURL: remoteURL, ref: ref,
                sizeKilobytes: repository.sizeKilobytes)
        }
    }

    /// A large repository asks first; adding to an existing shared clone never does, since nothing
    /// is downloaded.
    func requestClone(_ pending: PendingClone) {
        if !isAlreadyCloned(pending.remoteURL), sizePolicy.warrantsWarning(sizeKilobytes: pending.sizeKilobytes) {
            pendingLargeClone = pending
        } else {
            clone(pending, depth: .full)
        }
    }

    func clone(_ pending: PendingClone, depth: GitHistoryDepth) {
        clonePhase = .loading(.app("View.NewCodebaseSheet.Cloning"))
        Task {
            await model.editing.addRemoteCodebase(
                to: projectID, name: pending.name, remoteURL: pending.remoteURL, ref: pending.ref.name,
                refKind: pending.ref.kind, depth: depth)
            clonePhase = .loaded
            dismiss()
        }
    }

    /// The remote the chosen source points at, known before its ref is.
    var candidateRemoteURL: URL? {
        switch source {
        case .localFolder:
            nil
        case .remoteURL:
            RemoteAddress(text: remoteAddress).validURL
        case .gitHub:
            selectedRepository.flatMap(gitHubRemoteURL)
        }
    }

    func isAlreadyCloned(_ remoteURL: URL?) -> Bool {
        remoteURL != nil && isCandidateAlreadyCloned
    }

    func checkCandidateClone() async {
        guard let candidateRemoteURL else {
            isCandidateAlreadyCloned = false
            return
        }
        let endpoint = RemoteEndpoint(remoteURL: candidateRemoteURL, gitHubCredential: nil)
        let inspection = await remoteService.inspectClone(endpoint, hubStoreDirectory: model.store.gitRepositoriesDir)
        guard !Task.isCancelled else { return }
        isCandidateAlreadyCloned = inspection.isCloned
    }
}
