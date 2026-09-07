import SwiftUI
#if os(iOS)
import QuickLook
#else
import QuickLookUI
#endif

/// Read-only source preview backed by Quick Look — chosen over a custom syntax-highlighting stack
/// to avoid tokenizing/license-notice work. Tradeoff: Quick Look has no line/column API, so
/// `SourceLocation.line`/`.column` go unused here.
///
/// Presented as a `.sheet` on both platforms since `QLPreviewController` (iOS) and `QLPreviewView`
/// (macOS) have no shared SwiftUI wrapper; macOS skips `.inspector` since the call site
/// (`ViolationRowView`'s "View Source" button) sits deep in a scroll view, not a screen with its
/// own inspector column.
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
                        Button(.app("View.SourceViewerSheet.Done")) { dismiss() }
                            .accessibilityIdentifier("sourceViewer.dismissButton")
                    }
                }
        }
    }
}

#if os(iOS)
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
