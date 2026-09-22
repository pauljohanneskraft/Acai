import SwiftUI
import UniformTypeIdentifiers

/// Makes a project's sidebar row accept folders dragged in from Finder or Files, adding each as a
/// codebase of that project, and highlights the row while a drag hovers over it.
struct FolderDropTarget: ViewModifier {
    let projectID: UUID
    @ObservedObject var model: ProjectBrowserViewModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.2 : 0))
                    .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
                    .padding(-Spacing.xs)
            }
            .onDrop(of: FolderDropLoader.acceptedTypes, isTargeted: $isTargeted) { providers in
                Task { await add(providers) }
                return true
            }
    }

    private func add(_ providers: [NSItemProvider]) async {
        let loaded = await FolderDropLoader().folders(from: providers)
        if let failure = loaded.bookmarkFailures.first {
            model.store.report(
                .app("Error.ScopedResourceAccess.BookmarkFailed \(failure.path) \(failure.reason)"))
        }
        guard !loaded.folders.isEmpty else {
            model.store.report(.app("Error.FolderDropTarget.NoFoldersDropped"))
            return
        }
        let outcome = model.editing.addCodebases(from: loaded.folders, to: projectID)
        if outcome.alreadyPresent > 0 {
            model.store.report(.app("Error.FolderDropTarget.AlreadyAdded \(outcome.alreadyPresent)"))
        }
    }
}

/// Reads dropped items into folders. The bookmark and git detection run inside each provider's
/// background callback, because the drop's access grant only lasts that long.
struct FolderDropLoader {
    static let acceptedTypes: [UTType] = [.fileURL, .folder]

    struct Loaded {
        var folders: [DroppedFolder] = []
        var bookmarkFailures: [(path: String, reason: String)] = []
    }

    @MainActor
    func folders(from providers: [NSItemProvider]) async -> Loaded {
        var loaded = Loaded()
        for provider in providers {
            switch await folder(from: provider) {
            case .some(.success(let folder)):
                loaded.folders.append(folder)
            case .some(.failure(let failure)):
                loaded.folders.append(failure.folder)
                loaded.bookmarkFailures.append((failure.folder.url.path, failure.reason))
            case .none:
                continue
            }
        }
        return loaded
    }

    private struct BookmarkFailure: Error {
        let folder: DroppedFolder
        let reason: String
    }

    @MainActor
    private func folder(from provider: NSItemProvider) async -> Result<DroppedFolder, BookmarkFailure>? {
        await withCheckedContinuation { continuation in
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url.flatMap(read))
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier) {
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.folder.identifier) { url, inPlace, _ in
                    continuation.resume(returning: inPlace ? url.flatMap(read) : nil)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    private func read(_ url: URL) -> Result<DroppedFolder, BookmarkFailure>? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
        var folder = DroppedFolder(url: url)
        folder.repository = LocalGitRepositoryDetector(directory: url).detect()
        do {
            folder.securityScopedBookmark = try SecurityScopedBookmark(resolving: url)
        } catch {
            return .failure(BookmarkFailure(folder: folder, reason: error.localizedDescription))
        }
        return .success(folder)
    }
}
