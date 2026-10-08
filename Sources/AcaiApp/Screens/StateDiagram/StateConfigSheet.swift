import SwiftUI
import AcaiCore
import AcaiDiagram

/// Configuration popup for a value-flow state diagram: pick the variable whose assignments
/// define the state space, plus the max number of distinct states before analysis fails.
/// `StateConfigModel` owns the scope/variable rules; this renders them.
struct StateConfigSheet: View {
    let onCancel: () -> Void
    let onCreate: (StateDiagramConfiguration) -> Void

    @State private var model: StateConfigModel
    @State private var scopeQuery = ""
    @State private var variableQuery = ""

    init(
        artifact: CodeArtifact,
        initial: StateDiagramConfiguration? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (StateDiagramConfiguration) -> Void
    ) {
        self.onCancel = onCancel
        self.onCreate = onCreate
        _model = State(initialValue: StateConfigModel(artifact: artifact, initial: initial))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(.app("View.StateConfigSheet.PickVariablePossibleValues"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent {
                        VStack(alignment: .leading, spacing: .spacingXS) {
                            PickerFilterField(text: $scopeQuery)
                            Picker(.app("View.StateConfigSheet.Scope"), selection: scope) {
                                Text(.app("View.StateConfigSheet.Select")).tag(StateConfigModel.Scope?.none)
                                if model.hasGlobalVariables {
                                    Text(.app("View.StateConfigSheet.GlobalVariables"))
                                        .tag(StateConfigModel.Scope?.some(.globals))
                                }
                                let names = model.typeDisplayNames
                                let scopeIDs = model.typeIDsWithStoredProperties
                                    .filtered(by: scopeQuery, label: names.name(forID:))
                                ForEach(scopeIDs, id: \.self) { id in
                                    Text(verbatim: names.name(forID: id)).tag(StateConfigModel.Scope?.some(.type(id)))
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("stateConfig.scopePicker")
                        }
                    } label: {
                        Text(.app("View.StateConfigSheet.Scope"))
                    }

                    LabeledContent {
                        VStack(alignment: .leading, spacing: .spacingXS) {
                            PickerFilterField(text: $variableQuery)
                            Picker(.app("View.StateConfigSheet.Variable"), selection: $model.variableName) {
                                Text(.app("View.StateConfigSheet.Select")).tag("")
                                ForEach(model.variableNames.filtered(by: variableQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                            }
                            .labelsHidden()
                            .disabled(model.scope == nil)
                            .accessibilityIdentifier("stateConfig.variablePicker")
                        }
                    } label: {
                        Text(.app("View.StateConfigSheet.Variable"))
                    }

                    LabeledContent {
                        Stepper(value: $model.maxStates, in: 5...100, step: 5) {
                            Text(model.maxStates, format: .number)
                        }
                    } label: {
                        Text(.app("View.StateConfigSheet.MaxStates"))
                    }
                }
            }
            #if os(macOS)
            .frame(maxWidth: 460)
            #endif
            .navigationTitle(.app("View.StateConfigSheet.NewStateDiagram"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.StateConfigSheet.Cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.StateConfigSheet.Create")) { onCreate(model.configuration) }
                        .keyboardShortcut(.confirmDialog)
                        .disabled(!model.canCreate)
                        .accessibilityIdentifier("stateConfig.createButton")
                }
            }
        }
    }

    /// The scope picker goes through `selectScope` rather than the stored property, so a scope change
    /// takes the variable selection with it.
    private var scope: Binding<StateConfigModel.Scope?> {
        Binding(get: { model.scope }, set: { model.selectScope($0) })
    }
}
