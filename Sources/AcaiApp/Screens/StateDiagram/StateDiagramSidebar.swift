import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiQuality
import AcaiRender

enum StateDiagramSidebarTab {
    case settings, inspector
}

/// State Diagram's sidebar: folds `StateConfigSheet`'s variable-selection fields into a live
/// Settings tab, plus an Inspector tab for the selected state/transition.
///
/// Applying a new variable re-runs the whole analysis and drops state positions/undo history
/// (`StateDiagramViewModel.applyConfiguration`), so edits stage into a local draft applied only
/// on an explicit "Apply" tap rather than live-binding on every change.
struct StateDiagramSidebar: View {
    @ObservedObject var viewModel: StateDiagramViewModel
    let codebaseID: UUID
    @Binding var tab: StateDiagramSidebarTab
    let onApply: (StateDiagramConfiguration) -> Void
    let onApplyFilter: (AcaiQuality.Selector?) -> Void
    let onSaveAsFreeform: () -> Void
    let onExportImage: () -> Void

    @EnvironmentObject private var model: ProjectBrowserViewModel

    /// The staged variable choice, plus the scope/variable option lists it is picked from.
    @State private var config: StateConfigModel
    @State private var scopeQuery = ""
    @State private var variableQuery = ""

    init(
        viewModel: StateDiagramViewModel,
        codebaseID: UUID,
        tab: Binding<StateDiagramSidebarTab>,
        onApply: @escaping (StateDiagramConfiguration) -> Void,
        onApplyFilter: @escaping (AcaiQuality.Selector?) -> Void,
        onSaveAsFreeform: @escaping () -> Void,
        onExportImage: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.codebaseID = codebaseID
        self._tab = tab
        self.onApply = onApply
        self.onApplyFilter = onApplyFilter
        self.onSaveAsFreeform = onSaveAsFreeform
        self.onExportImage = onExportImage
        _config = State(initialValue: viewModel.draftConfiguration)
    }

    var body: some View {
        VStack(spacing: .zero) {
            Picker("", selection: $tab) {
                Text(.app("View.StateDiagramSidebar.Settings")).tag(StateDiagramSidebarTab.settings)
                Text(.app("View.StateDiagramSidebar.Inspector")).tag(StateDiagramSidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(.spacingS)

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
        guard let configuration = viewModel.configuration else { return config.scope == nil }
        let draft = config.configuration
        return draft.typeName == configuration.typeName
            && draft.variableName == configuration.variableName
            && draft.maxStates == configuration.maxStates
    }

    private var settingsContent: some View {
        Form {
            Section(.app("View.StateDiagramSidebar.Variable")) {
                Text(.app("View.StateDiagramSidebar.PickVariablePossibleValues"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $scopeQuery)
                        Picker(.app("View.StateDiagramSidebar.Scope"), selection: scope) {
                            Text(.app("View.StateDiagramSidebar.Select")).tag(StateConfigModel.Scope?.none)
                            if config.hasGlobalVariables {
                                Text(.app("View.StateDiagramSidebar.GlobalVariables"))
                                    .tag(StateConfigModel.Scope?.some(.globals))
                            }
                            let names = config.typeDisplayNames
                            let scopeIDs = config.typeIDsWithStoredProperties
                                .filtered(by: scopeQuery, label: names.name(forID:))
                            ForEach(scopeIDs, id: \.self) { id in
                                Text(verbatim: names.name(forID: id))
                                    .tag(StateConfigModel.Scope?.some(.type(id)))
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.stateSettings.scopePicker")
                    }
                } label: {
                    Text(.app("View.StateDiagramSidebar.Scope"))
                }

                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $variableQuery)
                        Picker(.app("View.StateDiagramSidebar.Variable"), selection: $config.variableName) {
                            Text(.app("View.StateDiagramSidebar.Select")).tag("")
                            ForEach(config.variableNames.filtered(by: variableQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(config.scope == nil)
                        .accessibilityIdentifier("diagram.stateSettings.variablePicker")
                    }
                } label: {
                    Text(.app("View.StateDiagramSidebar.Variable"))
                }

                LabeledContent {
                    Stepper(value: $config.maxStates, in: 5...100, step: 5) {
                        Text(config.maxStates, format: .number)
                    }
                } label: {
                    Text(.app("View.StateDiagramSidebar.MaxStates"))
                }

                Button(.app("View.StateDiagramSidebar.Apply"), action: apply)
                    .disabled(isDraftUnchanged || !config.canCreate)
                    .accessibilityIdentifier("diagram.stateSettings.applyButton")
            }

            DiagramFilterSection(
                filter: filterBinding,
                projectID: model.projectID(for: codebaseID) ?? codebaseID
            )

            Section(.app("View.StateDiagramSidebar.Export")) {
                Button(action: onSaveAsFreeform) {
                    Label(.app("View.StateDiagramSidebar.SaveFreeform"), systemImage: "document.on.document")
                }
                .help(.app("View.StateDiagramSidebar.SaveCopyEditableFreeform"))
                .disabled(viewModel.diagram == nil)
                .accessibilityIdentifier("diagram.saveAsFreeformButton")
                Button(action: onExportImage) {
                    Label(.app("View.StateDiagramSidebar.ExportImage"), systemImage: "photo")
                }
                .help(.app("View.StateDiagramSidebar.ExportDiagramImage"))
                .disabled(viewModel.diagram == nil)
                .accessibilityIdentifier("diagram.exportImageButton")
            }
        }
        .formStyle(.grouped)
    }

    private func apply() {
        onApply(config.configuration)
    }

    /// Goes through `selectScope` so a scope change drops a variable the new scope lacks.
    private var scope: Binding<StateConfigModel.Scope?> {
        Binding(get: { config.scope }, set: { config.selectScope($0) })
    }

    private var filterBinding: Binding<AcaiQuality.Selector?> {
        Binding(
            get: { viewModel.configuration?.filter },
            set: { onApplyFilter($0) }
        )
    }
}

/// Split into an extension to stay under the file's own type-body-length limit — same pattern
/// used for `SequenceDiagramSidebar+Inspector.swift`.
extension StateDiagramSidebar {
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
        VStack(spacing: .spacingM) {
            Image(systemName: "cursorarrow.click")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(.app("View.StateDiagramSidebar.SelectStateTransitionInspect"))
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
                stateFields(state)
                if let status = viewModel.stateDeltaStatus(stateID) {
                    ComparisonStatusRow(status: status)
                }
                stateTransitionGroups(outgoing: outgoing, incoming: incoming)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func stateFields(_ state: StateDiagram.State?) -> some View {
        LabeledContent {
            Text(verbatim: state?.kind.rawValue ?? "")
        } label: {
            Text(.app("View.StateDiagramSidebar.Kind"))
        }
        if let entryAction = state?.entryAction {
            LabeledContent {
                Text(verbatim: entryAction)
            } label: {
                Text(.app("View.StateDiagramSidebar.Entry"))
            }
        }
        if let exitAction = state?.exitAction {
            LabeledContent {
                Text(verbatim: exitAction)
            } label: {
                Text(.app("View.StateDiagramSidebar.Exit"))
            }
        }
        if let doActivity = state?.doActivity {
            LabeledContent {
                Text(verbatim: doActivity)
            } label: {
                Text(.app("View.StateDiagramSidebar.Do"))
            }
        }
    }

    @ViewBuilder
    private func stateTransitionGroups(
        outgoing: [StateDiagram.Transition], incoming: [StateDiagram.Transition]
    ) -> some View {
        if !outgoing.isEmpty {
            DisclosureGroup {
                ForEach(Array(outgoing.enumerated()), id: \.offset) { _, transition in
                    transitionRow(transition)
                }
            } label: {
                Text(.app("View.StateDiagramSidebar.Outgoing \(outgoing.count)"))
            }
        }
        if !incoming.isEmpty {
            DisclosureGroup {
                ForEach(Array(incoming.enumerated()), id: \.offset) { _, transition in
                    transitionRow(transition)
                }
            } label: {
                Text(.app("View.StateDiagramSidebar.Incoming \(incoming.count)"))
            }
        }
    }

    private func transitionRow(_ transition: StateDiagram.Transition) -> some View {
        HStack {
            transition.label.map { Text(verbatim: $0) } ?? Text(.app("View.StateDiagramSidebar.NoLabel"))
                .font(.caption.monospaced())
            Spacer()
            Text(verbatim: "\(viewModel.stateName(transition.from) ?? transition.from) → "
                 + "\(viewModel.stateName(transition.to) ?? transition.to)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func transitionDetail(_ transition: StateDiagram.Transition) -> some View {
        List {
            Section(.app("View.StateDiagramSidebar.Transition")) {
                LabeledContent {
                    Text(verbatim: viewModel.stateName(transition.from) ?? transition.from)
                } label: {
                    Text(.app("View.StateDiagramSidebar.From"))
                }
                LabeledContent {
                    Text(verbatim: viewModel.stateName(transition.to) ?? transition.to)
                } label: {
                    Text(.app("View.StateDiagramSidebar.To"))
                }
                if let event = transition.event {
                    LabeledContent {
                        Text(verbatim: event)
                    } label: {
                        Text(.app("View.StateDiagramSidebar.Event"))
                    }
                }
                if let guardCondition = transition.guardCondition {
                    LabeledContent {
                        Text(verbatim: guardCondition)
                    } label: {
                        Text(.app("View.StateDiagramSidebar.Guard"))
                    }
                }
                if let action = transition.action {
                    LabeledContent {
                        Text(verbatim: action)
                    } label: {
                        Text(.app("View.StateDiagramSidebar.Action"))
                    }
                }
                if let status = viewModel.transitionDeltaStatus(transition) {
                    ComparisonStatusRow(status: status)
                }
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
            title: { Text(.app("View.StateDiagramSidebar.StateInflectTrueSelected \($0)")) },
            rowIcon: { _ in nil },
            rowLabel: \.name,
            rowDetail: nil,
            onSelect: { viewModel.selectNode($0, extending: false) },
            bulkActions: []
        )
    }
}
