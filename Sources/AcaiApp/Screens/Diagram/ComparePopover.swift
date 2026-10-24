#if os(macOS)
import SwiftUI

/// Presented from the window's root: inside the detail column a comparison change drops it from the AX tree.
@MainActor
@Observable
final class ComparePopoverPresenter {
    private(set) var diagramID: UUID?
    /// Type ids of a changed file picked in the panel, for the open diagram to select and then clear.
    var changedFileSelection: Set<String>?
    private(set) var anchor = CompareAnchor()

    func isPresented(for diagramID: UUID) -> Bool {
        self.diagramID == diagramID
    }

    func setPresented(_ isPresented: Bool, for diagramID: UUID) {
        if isPresented {
            self.diagramID = diagramID
        } else if self.diagramID == diagramID {
            self.diagramID = nil
        }
        anchor.holdStill(self.diagramID != nil)
    }

    func close() {
        diagramID = nil
        anchor.holdStill(false)
    }

    func update(button frame: CGRect) {
        anchor.update(button: frame)
    }

    func update(host frame: CGRect) {
        anchor.update(host: frame)
    }
}

private struct ComparePopoverKey: EnvironmentKey {
    static let defaultValue: ComparePopoverPresenter? = nil
}

extension EnvironmentValues {
    /// `nil` outside a `ProjectBrowserView`, which has no compare popover to present.
    var comparePopover: ComparePopoverPresenter? {
        get { self[ComparePopoverKey.self] }
        set { self[ComparePopoverKey.self] = newValue }
    }
}

struct ComparePopoverPresentation: ViewModifier {
    let presenter: ComparePopoverPresenter
    let model: ProjectBrowserViewModel

    func body(content: Content) -> some View {
        let presentedDiagramID = presenter.diagramID
        let placement = presenter.anchor.placement ?? .zero
        content
            .environment(\.comparePopover, presenter)
            .background {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        presenter.update(host: frame)
                    }
                    .popover(
                        isPresented: Binding(
                            get: { presentedDiagramID != nil },
                            set: { if !$0 { presenter.close() } }),
                        attachmentAnchor: .rect(.rect(placement))
                    ) {
                        if let diagramID = presentedDiagramID {
                            ComparePopoverContent(diagramID: diagramID, presenter: presenter)
                                .environmentObject(model)
                        }
                    }
            }
    }
}

/// No `NavigationStack` toolbar: inside a macOS popover its items land in the window's toolbar.
private struct ComparePopoverContent: View {
    let diagramID: UUID
    let presenter: ComparePopoverPresenter
    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        if let diagram = model.generatedDiagram(for: diagramID) {
            VStack(alignment: .leading, spacing: .zero) {
                HStack {
                    Text(.app("View.CompareOverlayButton.CompareVsGit")).font(.headline)
                    Spacer()
                    CompareClearButton(diagram: diagram)
                }
                .padding()
                Divider()
                CompareGitPanel(
                    diagram: diagram,
                    onSelectChangedFileTypes: diagram.type.selectsChangedFileTypes
                        ? { presenter.changedFileSelection = $0 } : nil)
            }
        }
    }
}
#endif
