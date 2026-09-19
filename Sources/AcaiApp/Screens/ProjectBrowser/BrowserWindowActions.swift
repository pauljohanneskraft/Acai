import SwiftUI

/// What the menu bar can do with the key window's current selection.
struct BrowserWindowActions {
    var address: AppAddress?
    var copyLink: () -> Void
    var openInNewWindow: () -> Void
}

private struct BrowserWindowActionsKey: FocusedValueKey {
    typealias Value = BrowserWindowActions
}

extension FocusedValues {
    var browserWindowActions: BrowserWindowActions? {
        get { self[BrowserWindowActionsKey.self] }
        set { self[BrowserWindowActionsKey.self] = newValue }
    }
}

#if os(macOS)
struct BrowserWindowCommands: Commands {
    /// The `WindowGroup(id:for:)` a project, codebase or diagram opens in.
    static let windowID = "item"

    @FocusedValue(\.browserWindowActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(.app("View.BrowserWindowCommands.OpenInNewWindow")) {
                actions?.openInNewWindow()
            }
            .keyboardShortcut(.openInNewWindow)
            .disabled(actions?.address == nil)
            Button(.app("View.BrowserWindowCommands.CopyLink")) {
                actions?.copyLink()
            }
            .keyboardShortcut(.copyLink)
            .disabled(actions?.address == nil)
        }
    }
}

/// Hands the hosting `NSWindow` to `onWindow` once the view is in one, so another window can bring
/// this one to the front.
struct HostingWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
#endif
