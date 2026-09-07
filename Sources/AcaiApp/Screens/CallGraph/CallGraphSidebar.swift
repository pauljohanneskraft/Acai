import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiQuality

enum CallGraphSidebarTab {
    case settings, inspector
}

/// Applying a new scope rebuilds the whole graph (`CallGraphView`'s `.id(scope)` gives the canvas a
/// fresh identity, dropping positions/undo history), so scope edits stage into a local draft
/// applied only on an explicit "Apply" tap.
struct CallGraphSidebar: View {
    let artifact: CodeArtifact
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
    @Binding var showSaveAsFreeformOptions: Bool
    @Binding var includeMetricsNoteOnSave: Bool

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var draftScope: CallGraphScope
    @State private var scopeQuery = ""

    init(
        artifact: CodeArtifact,
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
        showSaveAsFreeformOptions: Binding<Bool>,
        includeMetricsNoteOnSave: Binding<Bool>
    ) {
        self.artifact = artifact
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
        self._showSaveAsFreeformOptions = showSaveAsFreeformOptions
        self._includeMetricsNoteOnSave = includeMetricsNoteOnSave
        _draftScope = State(initialValue: scope)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(.app("View.CallGraphSidebar.Settings")).tag(CallGraphSidebarTab.settings)
                Text(.app("View.CallGraphSidebar.Inspector")).tag(CallGraphSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .settings:
                settingsContent
                    .accessibilityIdentifier("diagram.sidebarContent.settings")
            case .inspector:
                CallGraphInspector(graph: graph, selectedNodeIDs: selectedNodeIDs, onSelect: onSelect)
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
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $scopeQuery)
                        Picker(.app("View.CallGraphSidebar.Scope"), selection: $draftScope) {
                            Text(.app("View.CallGraphSidebar.WholeCodebase")).tag(CallGraphScope.wholeCodebase)
                            let modules = moduleNames.filtered(by: scopeQuery)
                            if !modules.isEmpty {
                                Section(.app("View.CallGraphSidebar.Modules")) {
                                    ForEach(modules, id: \.self) { name in
                                        Text(verbatim: name).tag(CallGraphScope.module(name))
                                    }
                                }
                            }
                            Section(.app("View.CallGraphSidebar.Types")) {
                                ForEach(typeNames.filtered(by: scopeQuery), id: \.self) { name in
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

                Button(.app("View.CallGraphSidebar.Apply")) { onApplyScope(draftScope) }
                    .disabled(draftScope == scope)
                    .accessibilityIdentifier("diagram.callGraphSettings.applyButton")
            }

            DiagramFilterSection(
                filter: $filter,
                codebaseID: codebaseID,
                projectID: model.projectID(for: codebaseID) ?? codebaseID,
                artifact: artifact
            )

            Section(.app("View.CallGraphSidebar.Export")) {
                Button {
                    showSaveAsFreeformOptions = true
                } label: {
                    Label(.app("View.CallGraphSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.CallGraphSidebar.SaveCopyEditableFreeform"))
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                .saveAsFreeformOptions(
                    isPresented: $showSaveAsFreeformOptions,
                    includeMetricsNote: $includeMetricsNoteOnSave,
                    onConfirm: onSaveAsFreeform
                )
                Button(action: onExportImage) {
                    Label(.app("View.CallGraphSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.CallGraphSidebar.ExportDiagramImage"))
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Lookups
    // Duplicated from `CallGraphConfigSheet`, kept independent since that type is also the
    // creation-time flow presented from `CodebaseDetailView` and stays untouched.

    private var typeNames: [String] {
        artifact.types
            .filter { type in type.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    private var moduleNames: [String] {
        artifact.types
            .map { ModuleResolver.standard.productName(forFilePath: $0.location?.filePath ?? "") }
            .uniqued()
            .sorted()
    }
}
