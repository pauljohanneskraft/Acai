import SwiftUI
import AcaiCore
import AcaiDiagram
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
    @Binding var tab: SequenceDiagramSidebarTab
    let onApply: (SequenceDiagramConfiguration) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    @State private var draftEntryTypeName: String
    @State private var draftEntryMethodName: String
    @State private var draftMaxDepth: Int
    @State private var typeQuery = ""
    @State private var methodQuery = ""
    /// Non-empty only right after "Apply" finds abstractions along the traced path that have a
    /// resolvable conformer — mirrors `SequenceConfigSheet`'s second phase, inline instead of modal.
    @State private var pendingMappingRows: [MappingRow] = []

    private struct MappingRow: Identifiable {
        let id: String  // protocol name
        var protocolName: String { id }
        let candidates: [String]
        var selection: String?
    }

    init(
        viewModel: SequenceDiagramViewModel,
        artifact: CodeArtifact,
        tab: Binding<SequenceDiagramSidebarTab>,
        onApply: @escaping (SequenceDiagramConfiguration) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.artifact = artifact
        self._tab = tab
        self.onApply = onApply
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        _draftEntryTypeName = State(initialValue: viewModel.configuration.entryTypeName)
        _draftEntryMethodName = State(initialValue: viewModel.configuration.entryMethodName)
        _draftMaxDepth = State(initialValue: viewModel.configuration.maxDepth)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Settings").tag(SequenceDiagramSidebarTab.settings)
                Text("Inspector").tag(SequenceDiagramSidebarTab.inspector)
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
            Section("Entry Point") {
                Text("Choose where the trace begins. Applying re-runs the trace and resets any "
                     + "lifeline drags and undo history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Type") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $typeQuery)
                        Picker("Type", selection: $draftEntryTypeName) {
                            Text(freeFunctionNames.isEmpty ? "Select…" : "None (top-level functions)").tag("")
                            ForEach(callableTypeNames.filtered(by: typeQuery), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.sequenceSettings.typePicker")
                        .onChange(of: draftEntryTypeName) { _, _ in
                            if !draftMethodNames.contains(draftEntryMethodName) {
                                draftEntryMethodName = draftMethodNames.first ?? ""
                            }
                        }
                    }
                }

                LabeledContent(draftEntryTypeName.isEmpty ? "Function" : "Method") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $methodQuery)
                        Picker("Method", selection: $draftEntryMethodName) {
                            Text("Select…").tag("")
                            ForEach(draftMethodNames.filtered(by: methodQuery), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(draftMethodNames.isEmpty)
                        .accessibilityIdentifier("diagram.sequenceSettings.methodPicker")
                    }
                }

                LabeledContent("Max depth") {
                    Stepper(value: $draftMaxDepth, in: 1...20) {
                        Text("\(draftMaxDepth)")
                    }
                }

                Button("Apply", action: apply)
                    .disabled(isDraftUnchanged || draftEntryMethodName.isEmpty)
                    .accessibilityIdentifier("diagram.sequenceSettings.applyButton")
            }

            if !pendingMappingRows.isEmpty {
                Section("Resolve Interfaces") {
                    Text("These abstractions appear along the call path. Pick a concrete type to "
                         + "follow its implementation, or leave it abstract.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach($pendingMappingRows) { $row in
                        LabeledContent(row.protocolName) {
                            Picker(row.protocolName, selection: $row.selection) {
                                Text("Leave abstract").tag(String?.none)
                                ForEach(row.candidates, id: \.self) { Text($0).tag(String?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    }
                    Button("Apply Resolved Mapping", action: applyResolvedMapping)
                        .accessibilityIdentifier("diagram.sequenceSettings.applyResolvedMappingButton")
                }
            }

            Section("Export") {
                Button(action: onSaveAsFreeform) {
                    Label("Save as Freeform", systemImage: "document.on.document")
                }
                .help("Save a copy as an editable Freeform diagram")
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label("Export Image", systemImage: "photo")
                }
                .help("Export the diagram as an image")
                .disabled(viewModel.isEmpty)
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    /// Runs a first-pass trace; if any encountered participant is an abstraction with conformers,
    /// stage the resolution rows instead of applying immediately (mirrors `SequenceConfigSheet.advance()`).
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

    // MARK: - Selection Inspector

    @ViewBuilder
    private var selectionInspector: some View {
        if let messageID = viewModel.selectedMessageID, viewModel.orderedMessages.indices.contains(messageID) {
            messageDetail(viewModel.orderedMessages[messageID])
        } else if let participantID = viewModel.selectedNodeIDs.first, viewModel.selectedNodeIDs.count == 1 {
            participantDetail(participantID)
        } else if viewModel.selectedNodeIDs.count > 1 {
            multiSelectionList
        } else {
            emptyInspectorState
        }
    }

    private var emptyInspectorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Select a lifeline or message to inspect")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func participantDetail(_ participantID: String) -> some View {
        let name = viewModel.participantName(participantID) ?? participantID
        let sent = viewModel.orderedMessages.filter { $0.from == participantID }
        let received = viewModel.orderedMessages.filter { $0.to == participantID && $0.from != participantID }
        return List {
            Section(name) {
                if !sent.isEmpty {
                    DisclosureGroup("Sends (\(sent.count))") {
                        ForEach(Array(sent.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    }
                }
                if !received.isEmpty {
                    DisclosureGroup("Receives (\(received.count))") {
                        ForEach(Array(received.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func messageRow(_ message: SequenceDiagram.Message) -> some View {
        HStack {
            Text(message.label ?? message.kind.rawValue)
                .font(.caption.monospaced())
            Spacer()
            Text("\(viewModel.participantName(message.from) ?? message.from) → "
                 + "\(viewModel.participantName(message.to) ?? message.to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func messageDetail(_ message: SequenceDiagram.Message) -> some View {
        List {
            Section(message.label ?? "Message") {
                LabeledContent("From", value: viewModel.participantName(message.from) ?? message.from)
                LabeledContent("To", value: viewModel.participantName(message.to) ?? message.to)
                LabeledContent("Kind", value: message.kind.rawValue)
                LabeledContent("Order", value: "\(message.order)")
            }
        }
        .listStyle(.inset)
    }

    private var multiSelectionList: some View {
        List {
            Section("\(viewModel.selectedNodeIDs.count) Lifelines Selected") {
                ForEach(Array(viewModel.selectedNodeIDs).sorted(), id: \.self) { id in
                    Text(viewModel.participantName(id) ?? id)
                        .font(.caption.monospaced())
                }
            }
        }
        .listStyle(.inset)
    }
}
