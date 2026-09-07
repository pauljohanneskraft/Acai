import SwiftUI

/// Reveals a codebase-relative file path in Finder (macOS only) — a value you instantiate and call
/// `reveal()` on, factored out of `FinderRevealable`'s button wrapper so the same action can also
/// be offered as a **secondary** menu item alongside `CodeElementReferenceActions`' "Open in…"
/// resolution.
struct FinderReveal {
    let codebase: Codebase?
    let relativePath: String?
    /// Reveal can now fail for a reason worth telling the user about (the codebase's folder is
    /// gone, or the sandbox denies it) rather than silently doing nothing.
    var onFailure: ((Error) -> Void)?

    var isAvailable: Bool { codebase != nil && relativePath != nil }

    func reveal() {
        #if os(macOS)
        guard let codebase, let relativePath else { return }
        // `activateFileViewerSelecting` sends Finder a real Apple Event — skip it under a UI test
        // (same test-only gate `GitHubTokenStore`/`ProjectStore` use), since no test asserts on
        // Finder actually opening.
        guard UITestFixtureResolver().resolveBaseDir() == nil else { return }
        do {
            try codebase.revealInFinder(relativePath: relativePath)
        } catch {
            onFailure?(error)
        }
        #endif
    }
}

/// Disabled when `codebase` or `relativePath` is `nil`, or the file no longer exists on disk.
struct FinderRevealable: ViewModifier {
    let codebase: Codebase?
    let relativePath: String?

    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        Button {
            FinderReveal(
                codebase: codebase, relativePath: relativePath,
                onFailure: { errorMessage = $0.localizedDescription }
            ).reveal()
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!FinderReveal(codebase: codebase, relativePath: relativePath).isAvailable)
        .alert(
            .app("View.FinderRevealable.CouldNotRevealInFinder"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(.app("View.FinderRevealable.OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        #else
        // No Finder on iOS — pass through unwrapped rather than a tappable button that does nothing.
        content
        #endif
    }
}

extension View {
    func revealsInFinder(codebase: Codebase?, relativePath: String?) -> some View {
        modifier(FinderRevealable(codebase: codebase, relativePath: relativePath))
    }
}
