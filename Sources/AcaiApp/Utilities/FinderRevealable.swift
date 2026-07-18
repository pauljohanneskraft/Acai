import SwiftUI

/// Wraps `content` in a button that reveals `relativePath` (resolved against `codebase`'s directory)
/// in Finder — disabled when either is `nil`, or the file no longer exists on disk. `codebase` is
/// optional so a caller that doesn't (yet) have one on hand can still apply this unconditionally.
struct FinderRevealable: ViewModifier {
    let codebase: Codebase?
    let relativePath: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        Button {
            reveal()
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(codebase == nil || relativePath == nil)
        #else
        // No Finder on iOS — pass through unwrapped rather than presenting a tappable button that
        // does nothing. Tracked as a deferred feature (share sheet / "Open in Files" alternative).
        content
        #endif
    }

    #if os(macOS)
    private func reveal() {
        guard let codebase, let relativePath else { return }
        let url = URL(filePath: codebase.directoryPath).appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}

extension View {
    /// Makes this view clickable to reveal `relativePath` (resolved against `codebase`'s directory)
    /// in Finder. Not tappable when either argument is `nil`.
    func revealsInFinder(codebase: Codebase?, relativePath: String?) -> some View {
        modifier(FinderRevealable(codebase: codebase, relativePath: relativePath))
    }
}
