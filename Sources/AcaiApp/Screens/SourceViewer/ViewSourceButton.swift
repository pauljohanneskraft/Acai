import SwiftUI

/// Resolves `relativePath` off the main actor (touches the filesystem); on failure shows an
/// actionable alert, including a rejected path-escape/symlink-escape attempt from
/// `Codebase.resolvedFileURL`.
struct ViewSourceButton: View {
    let codebase: Codebase
    let relativePath: String

    @State private var isResolving = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var target: SourceViewerTarget?
    /// Keeps the codebase's security scope open for as long as Quick Look is presented — resolving
    /// a URL only needs the scope transiently (see `Codebase.resolvedFileURL`), but Quick Look reads
    /// the file lazily while the sheet stays up, so access must stay open until dismissal.
    @State private var longLivedAccess: ScopedResourceAccess.LongLivedAccess?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            resolve()
        } label: {
            if isResolving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(.app("View.ViewSourceButton.ViewSource"), systemImage: "doc.text.magnifyingglass")
            }
        }
        .disabled(isResolving)
        .accessibilityIdentifier("violation.viewSourceButton")
        .contextMenu {
            Button {
                resolve()
            } label: {
                Label(.app("View.ViewSourceButton.ViewSource"), systemImage: "doc.text.magnifyingglass")
            }
        }
        .sheet(item: $target, onDismiss: { longLivedAccess = nil }, content: { target in
            SourceViewerSheet(url: target.url)
        })
        .alert(
            .app("View.ViewSourceButton.CouldNotOpenFile"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(.app("View.ViewSourceButton.OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .onDisappear {
            resolveTask?.cancel()
        }
    }

    private func resolve() {
        resolveTask?.cancel()
        isResolving = true
        let codebase = codebase
        let relativePath = relativePath
        resolveTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try codebase.resolvedFileURL(relativePath: relativePath) }
            }.value
            guard !Task.isCancelled else { return }
            isResolving = false
            switch result {
            case .success(let url):
                longLivedAccess = ScopedResourceAccess.LongLivedAccess(
                    ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
                )
                target = SourceViewerTarget(url: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SourceViewerTarget: Identifiable {
    let id = UUID()
    let url: URL
}
