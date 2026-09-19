import SwiftUI

extension ProjectBrowserView {
    var windowActions: BrowserWindowActions {
        let selection = model.selection
        return BrowserWindowActions(
            address: selection?.address,
            copyLink: { selection?.address?.copyLinkToPasteboard() },
            openInNewWindow: { if let selection { openInNewWindow(selection) } }
        )
    }

    /// Keeps the one-window-per-diagram claim in step with what this window's detail column shows.
    func updateDiagramClaim(for selection: ProjectBrowserViewModel.Selection?) {
        if let diagramID = selection?.diagramID {
            browserWindows.claim(diagramID, for: windowToken)
        } else {
            browserWindows.release(windowToken)
        }
        if let windowAddress, let address = selection?.address, windowAddress.wrappedValue != address {
            windowAddress.wrappedValue = address
        }
    }

    func openLink(_ url: URL) {
        guard let selection = model.resolve(url: url) else { return }
        if let diagramID = selection.diagramID, browserWindows.isOpenElsewhere(diagramID, from: windowToken) {
            browserWindows.focusOwner(of: diagramID)
            return
        }
        model.selection = selection
    }

    func openInNewWindow(_ selection: ProjectBrowserViewModel.Selection) {
        #if os(macOS)
        guard let address = selection.address else { return }
        if let diagramID = selection.diagramID {
            if browserWindows.isOpenElsewhere(diagramID, from: windowToken) {
                browserWindows.focusOwner(of: diagramID)
                return
            }
            if model.selection?.diagramID == diagramID {
                model.selection = model.parentSelection(ofDiagram: diagramID)
                browserWindows.release(windowToken)
            }
        }
        openWindow(value: address)
        #endif
    }

    func diagramOpenElsewhere(_ diagramID: UUID) -> some View {
        ContentUnavailableView {
            Label(.app("View.ProjectBrowserView.DiagramOpenElsewhere"), systemImage: "macwindow.on.rectangle")
        } description: {
            Text(.app("View.ProjectBrowserView.DiagramOpenElsewhereDetail"))
        } actions: {
            Button(.app("View.ProjectBrowserView.ShowWindow")) {
                browserWindows.focusOwner(of: diagramID)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("diagramOpenElsewhere.showWindowButton")
        }
    }

    func addressMenuItems(for selection: ProjectBrowserViewModel.Selection, idPrefix: String) -> some View {
        AddressMenuItems(selection: selection, idPrefix: idPrefix)
    }
}

/// This window's "Open in New Window", handed to rows anywhere below `ProjectBrowserView`.
struct OpenInNewWindowAction {
    let open: (ProjectBrowserViewModel.Selection) -> Void

    func callAsFunction(_ selection: ProjectBrowserViewModel.Selection) {
        open(selection)
    }
}

extension EnvironmentValues {
    @Entry var openInNewWindow: OpenInNewWindowAction?
}

/// "Open in New Window" (macOS) and "Copy Link" for a row's context menu.
struct AddressMenuItems: View {
    let selection: ProjectBrowserViewModel.Selection
    let idPrefix: String
    @Environment(\.openInNewWindow) private var openInNewWindow

    var body: some View {
        if let address = selection.address {
            #if os(macOS)
            if let openInNewWindow {
                Button {
                    openInNewWindow(selection)
                } label: {
                    Label(.app("View.AddressMenuItems.OpenInNewWindow"), systemImage: "macwindow.badge.plus")
                }
                .accessibilityIdentifier("\(idPrefix).openInNewWindow")
            }
            #endif
            Button {
                address.copyLinkToPasteboard()
            } label: {
                Label(.app("View.AddressMenuItems.CopyLink"), systemImage: "link")
            }
            .accessibilityIdentifier("\(idPrefix).copyLink")
        }
    }
}

extension ProjectBrowserViewModel {
    /// Where a window lands when the diagram it showed moves to a window of its own.
    func parentSelection(ofDiagram diagramID: UUID) -> Selection? {
        if let diagram = store.generatedDiagrams[diagramID] { return .codebase(diagram.codebaseID) }
        return store.projects.first { $0.freeformDiagramIDs.contains(diagramID) }.map { .project($0.id) }
    }
}
