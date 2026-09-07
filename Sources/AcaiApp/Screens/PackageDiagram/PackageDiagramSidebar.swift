import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiQuality

enum PackageDiagramSidebarTab {
    case settings, inspector
}

/// Package Diagram's sidebar: a Settings tab (Export actions moved off the toolbar) plus
/// the selection-scoped Inspector (`PackageDiagramInspector`). Package Diagram has no entry-point/
/// scope configuration of its own (it always spans every build module) — the selector `filter` is
/// its first real configuration option, unlike Call Graph, which also folds its "Configure Scope"
/// sheet in here.
struct PackageDiagramSidebar: View {
    let diagram: PackageDiagram
    let selectedNodeIDs: Set<String>
    @Binding var filter: AcaiQuality.Selector?
    let codebaseID: UUID
    let artifact: CodeArtifact
    @Binding var tab: PackageDiagramSidebarTab
    let onSelect: (String) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void
    @Binding var showSaveAsFreeformOptions: Bool
    @Binding var includeMetricsNoteOnSave: Bool

    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(.app("View.PackageDiagramSidebar.Settings")).tag(PackageDiagramSidebarTab.settings)
                Text(.app("View.PackageDiagramSidebar.Inspector")).tag(PackageDiagramSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .settings:
                settingsContent
                    .accessibilityIdentifier("diagram.sidebarContent.settings")
            case .inspector:
                PackageDiagramInspector(diagram: diagram, selectedNodeIDs: selectedNodeIDs, onSelect: onSelect)
                    .accessibilityIdentifier("diagram.sidebarContent.inspector")
            }
        }
        .background {
            #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }

    private var settingsContent: some View {
        Form {
            DiagramFilterSection(
                filter: $filter,
                codebaseID: codebaseID,
                projectID: model.projectID(for: codebaseID) ?? codebaseID,
                artifact: artifact
            )

            Section(.app("View.PackageDiagramSidebar.Export")) {
                Button {
                    showSaveAsFreeformOptions = true
                } label: {
                    Label(.app("View.PackageDiagramSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.PackageDiagramSidebar.SaveCopyEditableFreeform"))
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                .saveAsFreeformOptions(
                    isPresented: $showSaveAsFreeformOptions,
                    includeMetricsNote: $includeMetricsNoteOnSave,
                    onConfirm: onSaveAsFreeform
                )
                Button(action: onExportImage) {
                    Label(.app("View.PackageDiagramSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.PackageDiagramSidebar.ExportDiagramImage"))
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }
}
