import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender

/// Sidebar tab choices for the sequence diagram, matching Class Diagram's closed vocabulary.
enum SequenceDiagramSidebarTab {
    case settings, inspector
}

/// Sequence Diagram's sidebar: folds `SequenceConfigSheet`'s entry-point/interface-resolution
/// fields into a live Settings tab (instead of a one-shot modal), and adds an Inspector tab showing
/// detail for the selected lifeline or message — neither existed before this pass.
///
/// Unlike Class Diagram's configuration, applying a new entry point re-runs the whole trace and
/// necessarily drops lifeline drags/undo history (`SequenceDiagramViewModel.applyConfiguration`), so
/// this can't live-bind on every keystroke the way Class Diagram's `Form` does — edits stage into a
/// local draft, applied only on an explicit "Apply" tap.
struct SequenceDiagramSidebar: View {
    @ObservedObject var viewModel: SequenceDiagramViewModel
    let artifact: CodeArtifact
    let codebaseID: UUID
    @Binding var tab: SequenceDiagramSidebarTab
    let onApply: (SequenceDiagramConfiguration) -> Void
    let onApplyFilter: (AcaiQuality.Selector?) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    @EnvironmentObject private var model: ProjectBrowserViewModel

    @State private var draftEntryTypeName: String
    @State private var draftEntryMethodName: String
    @State private var draftMaxDepth: Int
    @State private var typeQuery = ""
    @State private var methodQuery = ""
    /// Non-empty only right after "Apply" finds abstractions along the traced path that have a
    /// resolvable conformer — mirrors `SequenceConfigSheet`'s second phase, inline instead of modal.
    @State private var pendingMappingRows: [MappingRow] = []

    private struct MappingRow: Identifiable {
        let id: String
        var protocolName: String { id }
        let candidates: [String]
        var selection: String?
    }

    init(
        viewModel: SequenceDiagramViewModel,
        artifact: CodeArtifact,
        codebaseID: UUID,
        tab: Binding<SequenceDiagramSidebarTab>,
        onApply: @escaping (SequenceDiagramConfiguration) -> Void,
        onApplyFilter: @escaping (AcaiQuality.Selector?) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.artifact = artifact
        self.codebaseID = codebaseID
        self._tab = tab
        self.onApply = onApply
        self.onApplyFilter = onApplyFilter
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        _draftEntryTypeName = State(initialValue: viewModel.configuration.entryTypeName)
        _draftEntryMethodName = State(initialValue: viewModel.configuration.entryMethodName)
        _draftMaxDepth = State(initialValue: viewModel.configuration.maxDepth)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(.app("View.SequenceDiagramSidebar.Settings")).tag(SequenceDiagramSidebarTab.settings)
                Text(.app("View.SequenceDiagramSidebar.Inspector")).tag(SequenceDiagramSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .settings:
                settingsContent
                    .accessibilityIdentifier("diagram.sidebarContent.settings")
            case .inspector:
                selectionInspector
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

    // MARK: - Settings

    private var isDraftUnchanged: Bool {
        draftEntryTypeName == viewModel.configuration.entryTypeName
            && draftEntryMethodName == viewModel.configuration.entryMethodName
            && draftMaxDepth == viewModel.configuration.maxDepth
    }

    private var settingsContent: some View {
        Form {
            Section(.app("View.SequenceDiagramSidebar.EntryPoint")) {
                Text(.app("View.SequenceDiagramSidebar.ChooseWhereTraceBegins"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $typeQuery)
                        Picker(.app("View.SequenceDiagramSidebar.Type"), selection: $draftEntryTypeName) {
                            Text(localized: freeFunctionNames.isEmpty
                                ? .app("View.SequenceDiagramSidebar.SelectEllipsis")
                                : .app("View.SequenceDiagramSidebar.NoneTopLevelFunctions")).tag("")
                            ForEach(callableTypeNames.filtered(by: typeQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.sequenceSettings.typePicker")
                        .onChange(of: draftEntryTypeName) { _, _ in
                            if !draftMethodNames.contains(draftEntryMethodName) {
                                draftEntryMethodName = draftMethodNames.first ?? ""
                            }
                        }
                    }
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.Type"))
                }

                LabeledContent(draftEntryTypeName.isEmpty ? "Function" : "Method") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $methodQuery)
                        Picker(.app("View.SequenceDiagramSidebar.Method"), selection: $draftEntryMethodName) {
                            Text(.app("View.SequenceDiagramSidebar.Select")).tag("")
                            ForEach(draftMethodNames.filtered(by: methodQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(draftMethodNames.isEmpty)
                        .accessibilityIdentifier("diagram.sequenceSettings.methodPicker")
                    }
                }

                LabeledContent {
                    Stepper(value: $draftMaxDepth, in: 1...20) {
                        Text(draftMaxDepth, format: .number)
                    }
                } label: {
                    Text(.app("View.SequenceDiagramSidebar.MaxDepth"))
                }

                Button(.app("View.SequenceDiagramSidebar.Apply"), action: apply)
                    .disabled(isDraftUnchanged || draftEntryMethodName.isEmpty)
                    .accessibilityIdentifier("diagram.sequenceSettings.applyButton")
            }

            if !pendingMappingRows.isEmpty {
                Section(.app("View.SequenceDiagramSidebar.ResolveInterfaces")) {
                    Text(.app("View.SequenceDiagramSidebar.TheseAbstractionsAppearAlong"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach($pendingMappingRows) { $row in
                        LabeledContent(row.protocolName) {
                            Picker(row.protocolName, selection: $row.selection) {
                                Text(.app("View.SequenceDiagramSidebar.LeaveAbstract")).tag(String?.none)
                                ForEach(row.candidates, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    }
                    Button(.app("View.SequenceDiagramSidebar.ApplyResolvedMapping"), action: applyResolvedMapping)
                        .accessibilityIdentifier("diagram.sequenceSettings.applyResolvedMappingButton")
                }
            }

            DiagramFilterSection(
                filter: filterBinding,
                codebaseID: codebaseID,
                projectID: model.projectID(for: codebaseID) ?? codebaseID,
                artifact: artifact
            )

            Section(.app("View.SequenceDiagramSidebar.Export")) {
                Button(action: onSaveAsFreeform) {
                    Label(.app("View.SequenceDiagramSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.SequenceDiagramSidebar.SaveCopyEditableFreeform"))
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label(.app("View.SequenceDiagramSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.SequenceDiagramSidebar.ExportDiagramImage"))
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    /// Mirrors `SequenceConfigSheet.advance()`.
    private func apply() {
        let preview = SequenceDiagramBuilder(
            entryPoint: (draftEntryTypeName, draftEntryMethodName),
            maxDepth: draftMaxDepth
        ).build(from: artifact)
        var rows: [MappingRow] = []
        var seen: Set<String> = []
        for participant in preview.participants where !seen.contains(participant.name) {
            seen.insert(participant.name)
            let candidates = artifact.conformerNames(ofAbstractionNamed: participant.name)
            guard !candidates.isEmpty else { continue }
            rows.append(MappingRow(
                id: participant.name,
                candidates: candidates,
                selection: viewModel.configuration.typeMapping[participant.name]
            ))
        }
        if rows.isEmpty {
            onApply(SequenceDiagramConfiguration(
                entryTypeName: draftEntryTypeName, entryMethodName: draftEntryMethodName, maxDepth: draftMaxDepth
            ))
        } else {
            pendingMappingRows = rows
        }
    }

    private var filterBinding: Binding<AcaiQuality.Selector?> {
        Binding(
            get: { viewModel.configuration.filter },
            set: { onApplyFilter($0) }
        )
    }

    private func applyResolvedMapping() {
        var mapping: [String: String] = [:]
        for row in pendingMappingRows {
            if let concrete = row.selection { mapping[row.protocolName] = concrete }
        }
        onApply(SequenceDiagramConfiguration(
            entryTypeName: draftEntryTypeName, entryMethodName: draftEntryMethodName,
            maxDepth: draftMaxDepth, typeMapping: mapping
        ))
        pendingMappingRows = []
    }

    // MARK: - Lookups (duplicated from `SequenceConfigSheet`, kept independent since that type is
    // also the creation-time flow presented from `CodebaseDetailView` and stays untouched)

    private var freeFunctionNames: [String] {
        artifact.freestandingFunctions.map(\.name).uniqued().sorted()
    }

    private var callableTypeNames: [String] {
        artifact.types
            .filter { $0.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    private var draftMethodNames: [String] {
        guard !draftEntryTypeName.isEmpty else { return freeFunctionNames }
        guard let type = artifact.types.first(where: { $0.name == draftEntryTypeName }) else { return [] }
        return type.members
            .filter { $0.kind == .method }
            .map(\.name)
            .uniqued()
            .sorted()
    }

}
