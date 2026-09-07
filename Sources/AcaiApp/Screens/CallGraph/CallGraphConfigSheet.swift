import SwiftUI
import AcaiCore
import AcaiDiagram

struct CallGraphConfigSheet: View {
    let artifact: CodeArtifact
    let initial: CallGraphScope
    let onCancel: () -> Void
    let onCreate: (CallGraphScope) -> Void

    @State private var scope: CallGraphScope
    @State private var scopeQuery = ""

    init(
        artifact: CodeArtifact,
        initial: CallGraphScope = .wholeCodebase,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (CallGraphScope) -> Void
    ) {
        self.artifact = artifact
        self.initial = initial
        self.onCancel = onCancel
        self.onCreate = onCreate
        _scope = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.app("View.CallGraphConfigSheet.NewCallGraph"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text(.app("View.CallGraphConfigSheet.PickScopeEveryMethod"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $scopeQuery)
                        Picker(.app("View.CallGraphConfigSheet.Scope"), selection: $scope) {
                            Text(.app("View.CallGraphConfigSheet.WholeCodebase")).tag(CallGraphScope.wholeCodebase)
                            let modules = moduleNames.filtered(by: scopeQuery)
                            if !modules.isEmpty {
                                Section(.app("View.CallGraphConfigSheet.Modules")) {
                                    ForEach(modules, id: \.self) { name in
                                        Text(verbatim: name).tag(CallGraphScope.module(name))
                                    }
                                }
                            }
                            Section(.app("View.CallGraphConfigSheet.Types")) {
                                ForEach(typeNames.filtered(by: scopeQuery), id: \.self) { name in
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
                    .keyboardShortcut(.cancelAction)
                Button(.app("View.CallGraphConfigSheet.Create")) { onCreate(scope) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("callGraphConfig.createButton")
            }
        }
        .padding(20)
        .frame(maxWidth: 460)
    }

    // MARK: - Lookups

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
