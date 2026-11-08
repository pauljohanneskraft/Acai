import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiQuality

enum CallGraphSidebarTab {
    case settings, inspector
}

/// Applying a new scope rebuilds the whole graph (`CallGraphView`'s `.id(scope)` gives the canvas a
/// fresh identity, dropping positions/undo history), so scope edits stage into a local draft
/// applied only on an explicit "Apply" tap.
struct CallGraphSidebar: View {
    let graph: CallGraph
    let selectedNodeIDs: Set<String>
    let scope: CallGraphScope
    @Binding var filter: AcaiQuality.Selector?
    let codebaseID: UUID
    @Binding var tab: CallGraphSidebarTab
    let onSelect: (String) -> Void
    let onApplyScope: (CallGraphScope) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void
    /// `nil` for every id when the diagram isn't in delta mode.
    let deltaStatus: (String) -> DeltaStatus?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    /// The staged scope edit, plus the option lists it is picked from.
    @State private var config: CallGraphConfigModel
    @State private var scopeQuery = ""

    init(
        draftScope: CallGraphConfigModel,
        graph: CallGraph,
        selectedNodeIDs: Set<String>,
        scope: CallGraphScope,
        filter: Binding<AcaiQuality.Selector?>,
        codebaseID: UUID,
        tab: Binding<CallGraphSidebarTab>,
        onSelect: @escaping (String) -> Void,
        onApplyScope: @escaping (CallGraphScope) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void,
        deltaStatus: @escaping (String) -> DeltaStatus? = { _ in nil }
    ) {
        self.graph = graph
        self.selectedNodeIDs = selectedNodeIDs
        self.scope = scope
        self._filter = filter
        self.codebaseID = codebaseID
        self._tab = tab
        self.onSelect = onSelect
        self.onApplyScope = onApplyScope
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        self.deltaStatus = deltaStatus
        _config = State(initialValue: draftScope)
    }

    var body: some View {
        VStack(spacing: .zero) {
            Picker("", selection: $tab) {
                Text(.app("View.CallGraphSidebar.Settings")).tag(CallGraphSidebarTab.settings)
                Text(.app("View.CallGraphSidebar.Inspector")).tag(CallGraphSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(.spacingS)

            Divider()

            switch tab {
            case .settings:
                settingsContent
                    .accessibilityIdentifier("diagram.sidebarContent.settings")
            case .inspector:
                CallGraphInspector(
                    graph: graph, selectedNodeIDs: selectedNodeIDs, onSelect: onSelect, deltaStatus: deltaStatus
                )
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
            Section(.app("View.CallGraphSidebar.Scope")) {
                Text(.app("View.CallGraphSidebar.EveryMethodFreeFunction"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $scopeQuery)
                        Picker(.app("View.CallGraphSidebar.Scope"), selection: $config.scope) {
                            Text(.app("View.CallGraphSidebar.WholeCodebase")).tag(CallGraphScope.wholeCodebase)
                            let modules = config.moduleNames.filtered(by: scopeQuery)
                            if !modules.isEmpty {
                                Section(.app("View.CallGraphSidebar.Modules")) {
                                    ForEach(modules, id: \.self) { name in
                                        Text(verbatim: name).tag(CallGraphScope.module(name))
                                    }
                                }
                            }
                            Section(.app("View.CallGraphSidebar.Types")) {
                                ForEach(config.typeNames.filtered(by: scopeQuery), id: \.self) { name in
                                    Text(verbatim: name).tag(CallGraphScope.type(name))
                                }
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.callGraphSettings.scopePicker")
                    }
                } label: {
                    Text(.app("View.CallGraphSidebar.Scope"))
                }

                Button(.app("View.CallGraphSidebar.Apply")) { onApplyScope(config.scope) }
                    .disabled(config.scope == scope)
                    .accessibilityIdentifier("diagram.callGraphSettings.applyButton")
            }

            DiagramFilterSection(
                filter: $filter,
                projectID: model.projectID(for: codebaseID) ?? codebaseID
            )

            Section(.app("View.CallGraphSidebar.Export")) {
                Button(action: onSaveAsFreeform) {
                    Label(.app("View.CallGraphSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.CallGraphSidebar.SaveCopyEditableFreeform"))
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label(.app("View.CallGraphSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.CallGraphSidebar.ExportDiagramImage"))
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

}
