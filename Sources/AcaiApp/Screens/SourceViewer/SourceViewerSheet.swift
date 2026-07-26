import SwiftUI
#if os(iOS)
import QuickLook
#else
import QuickLookUI
#endif

/// Read-only source preview backed by Quick Look — the system's own document previewer (the same
/// one Files.app uses; there is no private, higher-fidelity viewer to reach for instead). Chosen
/// over a custom syntax-highlighting stack (originally spec'd around Highlightr) so this viewer
/// needs zero custom tokenizing, no new dependency, and no license-notice work. The tradeoff, taken
/// deliberately: Quick Look has no line/column addressing API, so jump-to-line isn't possible here —
/// `SourceLocation.line`/`.column` go unused by this view (see `BACKLOG.md` B30).
///
/// Presented as a `.sheet` on **both** platforms for this call site (`ViolationRowView`'s "View
/// Source" button): `QLPreviewController` (iOS/iPadOS) and `QLPreviewView` (macOS, via
/// `QuickLookUI`) are genuinely different API families with no single shared SwiftUI wrapper, but
/// macOS deliberately doesn't reach for `.inspector` here — this call site is a report row nested
/// arbitrarily deep in a scroll view, not a screen that owns its own inspector column, so a real
/// side-pane presentation would mean plumbing state up through several intermediate views (that's
/// the kind of multi-row wiring `BACKLOG.md` B29 owns, not this proof-of-concept item).
struct SourceViewerSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                #if os(iOS)
                .ignoresSafeArea(edges: .bottom)
                #else
                .frame(minWidth: 480, minHeight: 360)
                #endif
                .navigationTitle(url.lastPathComponent)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("sourceViewer.dismissButton")
                    }
                }
        }
    }
}

#if os(iOS)
/// Wraps `QLPreviewController` (UIKit-only — there is no SwiftUI-native Quick Look view on iOS).
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    /// Retained by `Context` for the representable's lifetime — an inline data source would
    /// deallocate immediately and `QLPreviewController` would show a blank preview.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#else
/// Wraps `QLPreviewView` (QuickLookUI, macOS-only) — the embeddable Quick Look API, simpler to host
/// inside a SwiftUI view than the shared-singleton `QLPreviewPanel`.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        guard (nsView.previewItem?.previewItemURL) != url else { return }
        nsView.previewItem = url as NSURL
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}
#endif
