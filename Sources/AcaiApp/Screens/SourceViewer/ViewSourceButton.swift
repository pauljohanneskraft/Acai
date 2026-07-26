import SwiftUI

/// Resolves `relativePath` against `codebase` off the main actor (`USABILITY_GUARDRAILS.md` §1 —
/// this touches the filesystem) and presents it in a read-only `SourceViewerSheet` (Quick Look) on
/// success, or a specific, actionable alert on failure (a missing file, or a rejected path-escape/
/// symlink-escape attempt from `Codebase.resolvedFileURL`). The one end-to-end "View Source" call
/// site for `BACKLOG.md` B30 — wired into `ViolationRowView`; every other row that could use the
/// same action (dead-code/health rows, stat-detail rows) is B29's follow-on work.
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
                Label("View Source", systemImage: "doc.text.magnifyingglass")
            }
        }
        .disabled(isResolving)
        .accessibilityIdentifier("violation.viewSourceButton")
        .contextMenu {
            // Mirrors the button's own action — `USABILITY_GUARDRAILS.md` §8 makes a context-menu
            // entry the universal baseline discovery path alongside the always-visible button.
            Button {
                resolve()
            } label: {
                Label("View Source", systemImage: "doc.text.magnifyingglass")
            }
        }
        .sheet(item: $target, onDismiss: { longLivedAccess = nil }, content: { target in
            SourceViewerSheet(url: target.url)
        })
        .alert(
            "Couldn't Open File",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
