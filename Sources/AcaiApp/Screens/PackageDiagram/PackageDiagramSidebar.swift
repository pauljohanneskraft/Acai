import SwiftUI
import AcaiDiagram

/// Sidebar tab choices for the package diagram, matching Class Diagram's closed vocabulary.
enum PackageDiagramSidebarTab {
    case settings, inspector
}

/// Package Diagram's sidebar: a Settings tab (Export actions moved off the toolbar) plus
/// the selection-scoped Inspector (`PackageDiagramInspector`). Package Diagram has no scope
/// configuration of its own (it always spans every build module), so Settings here is just Export —
/// unlike Call Graph, which also folds its "Configure Scope" sheet in here.
struct PackageDiagramSidebar: View {
    let diagram: PackageDiagram
    let selectedNodeIDs: Set<String>
    @Binding var tab: PackageDiagramSidebarTab
    let onSelect: (String) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void
    @Binding var showSaveAsFreeformOptions: Bool
    @Binding var includeMetricsNoteOnSave: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Settings").tag(PackageDiagramSidebarTab.settings)
                Text("Inspector").tag(PackageDiagramSidebarTab.inspector)
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
            Section("Export") {
                Button {
                    showSaveAsFreeformOptions = true
                } label: {
                    Label("Save as Freeform", systemImage: "document.on.document")
                }
                .help("Save a copy as an editable Freeform diagram")
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                .saveAsFreeformOptions(
                    isPresented: $showSaveAsFreeformOptions,
                    includeMetricsNote: $includeMetricsNoteOnSave,
                    onConfirm: onSaveAsFreeform
                )
                Button(action: onExportImage) {
                    Label("Export Image", systemImage: "photo")
                }
                .help("Export the diagram as an image")
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }
}
