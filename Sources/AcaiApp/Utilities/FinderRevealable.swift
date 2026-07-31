import SwiftUI

/// Reveals a codebase-relative file path in Finder (macOS only) — a value you instantiate and call
/// `reveal()` on. The action itself, factored out of `FinderRevealable`'s button wrapper so the same
/// action can also be offered as a **secondary** menu item alongside `CodeElementReferenceActions`'
/// "Open in…" resolution — the fix for surfaces that used to have Finder-reveal as their
/// *only* action, which is inert on iOS/iPadOS (see below).
struct FinderReveal {
    let codebase: Codebase?
    let relativePath: String?

    /// Whether there's anything to reveal — both a codebase and a relative path are known.
    var isAvailable: Bool { codebase != nil && relativePath != nil }

    func reveal() {
        #if os(macOS)
        guard let codebase, let relativePath else { return }
        // `activateFileViewerSelecting` sends Finder a real Apple Event — skip it under a UI test
        // (same test-only gate `GitHubTokenStore`/`ProjectStore` use), since no test asserts on
        // Finder actually opening.
        guard UITestFixtureResolver().resolveBaseDir() == nil else { return }
        guard let url = try? codebase.resolvedFileURL(relativePath: relativePath) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}

/// Wraps `content` in a button that reveals `relativePath` (resolved against `codebase`'s directory)
/// in Finder — disabled when either is `nil`, or the file no longer exists on disk. `codebase` is
/// optional so a caller that doesn't (yet) have one on hand can still apply this unconditionally.
struct FinderRevealable: ViewModifier {
    let codebase: Codebase?
    let relativePath: String?

    private var reveal: FinderReveal { FinderReveal(codebase: codebase, relativePath: relativePath) }

    func body(content: Content) -> some View {
        #if os(macOS)
        Button {
            reveal.reveal()
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!reveal.isAvailable)
        #else
        // No Finder on iOS — pass through unwrapped rather than a tappable button that does nothing.
        content
        #endif
    }
}

extension View {
    /// Makes this view clickable to reveal `relativePath` (resolved against `codebase`'s directory)
    /// in Finder. Not tappable when either argument is `nil`.
    func revealsInFinder(codebase: Codebase?, relativePath: String?) -> some View {
        modifier(FinderRevealable(codebase: codebase, relativePath: relativePath))
    }
}
