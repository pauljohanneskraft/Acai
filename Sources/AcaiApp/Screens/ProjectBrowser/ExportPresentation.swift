import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Hands `ProjectBrowserViewModel.pendingExport` to the platform's convention: a save panel on
/// macOS, the system share sheet (with Save to Files among its options) on iOS and iPadOS.
struct ExportPresentation: ViewModifier {
    @ObservedObject var model: ProjectBrowserViewModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onChange(of: model.pendingExport?.id) { _, id in
                if id != nil { sharePendingExport() }
            }
        #else
        content
            .fileExporter(
                isPresented: Binding(
                    get: { model.pendingExport != nil },
                    set: { if !$0 { model.pendingExport = nil } }
                ),
                document: model.pendingExport.map { ExportDocument(data: $0.data) },
                contentType: model.pendingExport?.contentType ?? .data,
                defaultFilename: model.pendingExport?.filename
            ) { result in
                if case .failure(let error) = result {
                    model.store.report(.app("Error.ProjectBrowserView.ExportFailed \(error.localizedDescription)"))
                }
                model.pendingExport = nil
            }
        #endif
    }

    #if os(iOS)
    private func sharePendingExport() {
        guard let export = model.pendingExport else { return }
        model.pendingExport = nil
        let data = export.data
        let filename = export.filename
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ExportStaging.standard.stage(data, as: filename) }
            }.value
            do {
                try ExportShareSheet(fileURL: result.get().fileURL).present()
            } catch {
                model.store.report(.app("Error.ProjectBrowserView.ExportFailed \(error.localizedDescription)"))
            }
        }
    }
    #endif
}

#if os(iOS)
/// Presented through UIKit from the top-most controller rather than as a SwiftUI sheet, because an
/// export is usually started from inside a presentation (the compact-width diagram inspector) that a
/// sheet on the project browser could not stack on top of.
@MainActor
private struct ExportShareSheet {
    let fileURL: URL

    enum Failure: LocalizedError {
        case noWindow

        var errorDescription: String? {
            String(localized: .app("Error.ExportShareSheet.NoWindow"))
        }
    }

    func present() throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
            ?? scenes.lazy.compactMap(\.keyWindow).first
        guard var presenter = window?.rootViewController else { throw Failure.noWindow }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in ExportStaging.standard.discardAll() }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            let bounds = presenter.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}
#endif
