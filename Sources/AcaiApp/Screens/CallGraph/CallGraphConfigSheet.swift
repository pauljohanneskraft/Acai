import SwiftUI
import AcaiCore
import AcaiDiagram

/// `CallGraphConfigModel` owns the scope rules and the option lists; this renders them.
struct CallGraphConfigSheet: View {
    let onCancel: () -> Void
    let onCreate: (CallGraphScope) -> Void

    @State private var model: CallGraphConfigModel
    @State private var scopeQuery = ""

    init(
        artifact: CodeArtifact,
        initial: CallGraphScope = .wholeCodebase,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (CallGraphScope) -> Void
    ) {
        self.onCancel = onCancel
        self.onCreate = onCreate
        _model = State(initialValue: CallGraphConfigModel(artifact: artifact, initial: initial))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingL) {
            Text(.app("View.CallGraphConfigSheet.NewCallGraph"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: .spacingM) {
                Text(.app("View.CallGraphConfigSheet.PickScopeEveryMethod"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $scopeQuery)
                        Picker(.app("View.CallGraphConfigSheet.Scope"), selection: $model.scope) {
                            Text(.app("View.CallGraphConfigSheet.WholeCodebase")).tag(CallGraphScope.wholeCodebase)
                            let modules = model.moduleNames.filtered(by: scopeQuery)
                            if !modules.isEmpty {
                                Section(.app("View.CallGraphConfigSheet.Modules")) {
                                    ForEach(modules, id: \.self) { name in
                                        Text(verbatim: name).tag(CallGraphScope.module(name))
                                    }
                                }
                            }
                            Section(.app("View.CallGraphConfigSheet.Types")) {
                                ForEach(model.typeNames.filtered(by: scopeQuery), id: \.self) { name in
                                    Text(verbatim: name).tag(CallGraphScope.type(name))
                                }
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("callGraphConfig.scopePicker")
                    }
                } label: {
                    Text(.app("View.CallGraphConfigSheet.Scope"))
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(.app("View.CallGraphConfigSheet.Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelDialog)
                Button(.app("View.CallGraphConfigSheet.Create")) { onCreate(model.scope) }
                    .keyboardShortcut(.confirmDialog)
                    .accessibilityIdentifier("callGraphConfig.createButton")
            }
        }
        .padding(.spacingL)
        .frame(maxWidth: 460)
    }
}
