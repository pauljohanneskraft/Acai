import SwiftUI
import AcaiCore
import AcaiDiagram

/// Sidebar tab choices for the call graph, matching Class Diagram's closed vocabulary.
enum CallGraphSidebarTab {
    case settings, inspector
}

/// Call Graph's sidebar: folds `CallGraphConfigSheet`'s scope picker into a live Settings
/// tab (instead of a one-shot modal) plus Export actions moved off the toolbar, and makes the
/// Inspector tab selection-scoped (`CallGraphInspector`).
///
/// Applying a new scope rebuilds the whole graph (`CallGraphView`'s `.id(scope)` gives the canvas a
/// fresh identity, dropping positions/undo history), so — like Sequence/State — scope edits stage
/// into a local draft applied only on an explicit "Apply" tap.
struct CallGraphSidebar: View {
    let artifact: CodeArtifact
    let graph: CallGraph
    let selectedNodeIDs: Set<String>
    let scope: CallGraphScope
    @Binding var tab: CallGraphSidebarTab
    let onSelect: (String) -> Void
    let onApplyScope: (CallGraphScope) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void
    @Binding var showSaveAsFreeformOptions: Bool
    @Binding var includeMetricsNoteOnSave: Bool

    @State private var draftScope: CallGraphScope
    @State private var scopeQuery = ""

    init(
        artifact: CodeArtifact,
        graph: CallGraph,
        selectedNodeIDs: Set<String>,
        scope: CallGraphScope,
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
                Text("Settings").tag(CallGraphSidebarTab.settings)
                Text("Inspector").tag(CallGraphSidebarTab.inspector)
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
            Section("Scope") {
                Text("Every method (and free function) in scope becomes a caller; each "
                     + "statically-resolvable call is an edge. Applying re-derives the graph and "
                     + "resets positions and undo history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Scope") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $scopeQuery)
                        Picker("Scope", selection: $draftScope) {
                            Text("Whole Codebase").tag(CallGraphScope.wholeCodebase)
                            let modules = moduleNames.filtered(by: scopeQuery)
                            if !modules.isEmpty {
                                Section("Modules") {
                                    ForEach(modules, id: \.self) { name in
                                        Text(name).tag(CallGraphScope.module(name))
                                    }
                                }
                            }
                            Section("Types") {
                                ForEach(typeNames.filtered(by: scopeQuery), id: \.self) { name in
                                    Text(name).tag(CallGraphScope.type(name))
                                }
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.callGraphSettings.scopePicker")
                    }
                }

                Button("Apply") { onApplyScope(draftScope) }
                    .disabled(draftScope == scope)
                    .accessibilityIdentifier("diagram.callGraphSettings.applyButton")
            }

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

    // MARK: - Lookups (duplicated from `CallGraphConfigSheet`, kept independent since that type is
    // also the creation-time flow presented from `CodebaseDetailView` and stays untouched)

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
