import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender

/// Sidebar tab choices for the state diagram, matching Class Diagram's closed vocabulary.
enum StateDiagramSidebarTab {
    case settings, inspector
}

/// State Diagram's sidebar: folds `StateConfigSheet`'s variable-selection fields into a live
/// Settings tab (instead of a one-shot modal), and adds an Inspector tab showing detail for the
/// selected state or transition — neither existed before this pass.
///
/// Like Sequence Diagram, applying a new variable re-runs the whole analysis and drops state
/// positions/undo history (`StateDiagramViewModel.applyConfiguration`), so edits stage into a local
/// draft applied only on an explicit "Apply" tap rather than live-binding on every change.
struct StateDiagramSidebar: View {
    @ObservedObject var viewModel: StateDiagramViewModel
    let artifact: CodeArtifact
    @Binding var tab: StateDiagramSidebarTab
    let onApply: (StateDiagramConfiguration) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    /// Where the variable lives: a type, or the module/global scope. Mirrors `StateConfigSheet`'s
    /// own private `Scope`, duplicated rather than shared since that sheet stays untouched (it's
    /// also the creation-time flow presented from `CodebaseDetailView`).
    private enum Scope: Hashable {
        case type(String)
        case globals
    }

    @State private var draftScope: Scope?
    @State private var draftVariableName: String
    @State private var draftMaxStates: Int
    @State private var scopeQuery = ""
    @State private var variableQuery = ""

    init(
        viewModel: StateDiagramViewModel,
        artifact: CodeArtifact,
        tab: Binding<StateDiagramSidebarTab>,
        onApply: @escaping (StateDiagramConfiguration) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.artifact = artifact
        self._tab = tab
        self.onApply = onApply
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        if let configuration = viewModel.configuration {
            _draftScope = State(initialValue: configuration.typeName.map(Scope.type) ?? .globals)
            _draftVariableName = State(initialValue: configuration.variableName)
            _draftMaxStates = State(initialValue: configuration.maxStates)
        } else {
            _draftScope = State(initialValue: nil)
            _draftVariableName = State(initialValue: "")
            _draftMaxStates = State(initialValue: 20)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Settings").tag(StateDiagramSidebarTab.settings)
                Text("Inspector").tag(StateDiagramSidebarTab.inspector)
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
        guard let configuration = viewModel.configuration else { return draftScope == nil }
        let draftTypeName: String? = if case .type(let name) = draftScope { name } else { nil }
        return draftTypeName == configuration.typeName
            && draftVariableName == configuration.variableName
            && draftMaxStates == configuration.maxStates
    }

    private var settingsContent: some View {
        Form {
            Section("Variable") {
                Text("Pick a variable. Its possible values (\"states\") are inferred from "
                     + "assignments across the codebase. Applying re-runs the analysis and resets "
                     + "any state drags and undo history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Scope") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $scopeQuery)
                        Picker("Scope", selection: $draftScope) {
                            Text("Select…").tag(Scope?.none)
                            if !artifact.globalVariables.isEmpty {
                                Text("Global Variables").tag(Scope?.some(.globals))
                            }
                            ForEach(typeNamesWithStoredProperties.filtered(by: scopeQuery), id: \.self) { name in
                                Text(name).tag(Scope?.some(.type(name)))
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.stateSettings.scopePicker")
                        .onChange(of: draftScope) { _, _ in
                            if !draftVariableNames.contains(draftVariableName) {
                                draftVariableName = draftVariableNames.first ?? ""
                            }
                        }
                    }
                }

                LabeledContent("Variable") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $variableQuery)
                        Picker("Variable", selection: $draftVariableName) {
                            Text("Select…").tag("")
                            ForEach(draftVariableNames.filtered(by: variableQuery), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(draftScope == nil)
                        .accessibilityIdentifier("diagram.stateSettings.variablePicker")
                    }
                }

                LabeledContent("Max states") {
                    Stepper(value: $draftMaxStates, in: 5...100, step: 5) {
                        Text("\(draftMaxStates)")
                    }
                }

                Button("Apply", action: apply)
                    .disabled(isDraftUnchanged || draftScope == nil || draftVariableName.isEmpty)
                    .accessibilityIdentifier("diagram.stateSettings.applyButton")
            }

            Section("Export") {
                Button(action: onSaveAsFreeform) {
                    Label("Save as Freeform", systemImage: "document.on.document")
                }
                .help("Save a copy as an editable Freeform diagram")
                .disabled(viewModel.diagram == nil)
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label("Export Image", systemImage: "photo")
                }
                .help("Export the diagram as an image")
                .disabled(viewModel.diagram == nil)
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    private func apply() {
        let typeName: String? = if case .type(let name) = draftScope { name } else { nil }
        onApply(StateDiagramConfiguration(
            typeName: typeName, variableName: draftVariableName, maxStates: draftMaxStates
        ))
    }

    // MARK: - Lookups (duplicated from `StateConfigSheet`, kept independent since that type is also
    // the creation-time flow presented from `CodebaseDetailView` and stays untouched)

    private var typesWithStoredProperties: [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.members.contains(where: { $0.kind == .property && !$0.isComputed }) {
                    result.append(type)
                }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return result
    }

    private var typeNamesWithStoredProperties: [String] {
        typesWithStoredProperties.map(\.qualifiedName).uniqued().sorted()
    }

    private var draftVariableNames: [String] {
        let members: [Member]
        switch draftScope {
        case .type(let qualifiedName):
            members = typesWithStoredProperties.first { $0.qualifiedName == qualifiedName }?
                .members.filter { $0.kind == .property && !$0.isComputed } ?? []
        case .globals:
            members = artifact.globalVariables
        case nil:
            return []
        }
        let plausible = members.filter { isPlausibleStateHolder($0) }.map(\.name)
        let rest = members.filter { !isPlausibleStateHolder($0) }.map(\.name)
        return (plausible.uniqued().sorted() + rest.uniqued().sorted()).uniqued()
    }

    private func isPlausibleStateHolder(_ member: Member) -> Bool {
        guard let typeName = member.type?.name else { return false }
        if enumTypeNames.contains(typeName) { return true }
        let simple = typeName.lowercased()
        return ["bool", "boolean", "int", "integer", "string"].contains(simple)
    }

    private var enumTypeNames: Set<String> {
        var names: Set<String> = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.kind == .enum { names.insert(type.name) }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return names
    }

    // MARK: - Selection Inspector

    @ViewBuilder
    private var selectionInspector: some View {
        if let transitionID = viewModel.selectedTransitionID,
           let transition = viewModel.diagram?.transitions[safe: transitionID] {
            transitionDetail(transition)
        } else if let stateID = viewModel.selectedNodeIDs.first, viewModel.selectedNodeIDs.count == 1 {
            stateDetail(stateID)
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
            Text("Select a state or transition to inspect")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateDetail(_ stateID: String) -> some View {
        let state = viewModel.diagram?.states.first { $0.id == stateID }
        let outgoing = viewModel.diagram?.transitions.filter { $0.from == stateID } ?? []
        let incoming = viewModel.diagram?.transitions.filter { $0.to == stateID } ?? []
        return List {
            Section(state?.name ?? stateID) {
                LabeledContent("Kind", value: state?.kind.rawValue ?? "")
                if let entryAction = state?.entryAction { LabeledContent("Entry", value: entryAction) }
                if let exitAction = state?.exitAction { LabeledContent("Exit", value: exitAction) }
                if let doActivity = state?.doActivity { LabeledContent("Do", value: doActivity) }
                if !outgoing.isEmpty {
                    DisclosureGroup("Outgoing (\(outgoing.count))") {
                        ForEach(Array(outgoing.enumerated()), id: \.offset) { _, transition in
                            transitionRow(transition)
                        }
                    }
                }
                if !incoming.isEmpty {
                    DisclosureGroup("Incoming (\(incoming.count))") {
                        ForEach(Array(incoming.enumerated()), id: \.offset) { _, transition in
                            transitionRow(transition)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func transitionRow(_ transition: StateDiagram.Transition) -> some View {
        HStack {
            Text(transition.label ?? "(no label)")
                .font(.caption.monospaced())
            Spacer()
            Text("\(viewModel.stateName(transition.from) ?? transition.from) → "
                 + "\(viewModel.stateName(transition.to) ?? transition.to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func transitionDetail(_ transition: StateDiagram.Transition) -> some View {
        List {
            Section("Transition") {
                LabeledContent("From", value: viewModel.stateName(transition.from) ?? transition.from)
                LabeledContent("To", value: viewModel.stateName(transition.to) ?? transition.to)
                if let event = transition.event { LabeledContent("Event", value: event) }
                if let guardCondition = transition.guardCondition { LabeledContent("Guard", value: guardCondition) }
                if let action = transition.action { LabeledContent("Action", value: action) }
            }
        }
        .listStyle(.inset)
    }

    private struct SelectableState: Identifiable {
        let id: String
        let name: String
    }

    private var multiSelectionList: some View {
        let selected = viewModel.selectedNodeIDs.sorted()
            .map { SelectableState(id: $0, name: viewModel.stateName($0) ?? $0) }
        return MultiSelectionInspector(
            items: selected,
            title: { Text("^[\($0) State](inflect: true) Selected") },
            rowIcon: { _ in nil },
            rowLabel: \.name,
            rowDetail: nil,
            onSelect: { viewModel.selectNode($0, extending: false) },
            bulkAction: nil
        )
    }
}
