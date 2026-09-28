import SwiftUI
import AcaiCore
import AcaiDiagram

/// Two-phase configuration popup for a sequence diagram — `SequenceConfigModel` owns the steps and
/// the option lists; this renders them.
///
/// 1. **Entry point** — pick the starting type and method, and a maximum call depth.
/// 2. **Interface resolution** — a first-pass trace runs, then a concrete-type dropdown is
///    offered for each protocol/interface actually encountered (and that has a conformer), so
///    the diagram can follow real implementations instead of stopping at an abstraction.
struct SequenceConfigSheet: View {
    let onCancel: () -> Void
    let onCreate: (SequenceDiagramConfiguration) -> Void

    @State private var model: SequenceConfigModel
    @State private var typeQuery = ""
    @State private var methodQuery = ""

    init(
        artifact: CodeArtifact,
        initial: SequenceDiagramConfiguration? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (SequenceDiagramConfiguration) -> Void
    ) {
        self.onCancel = onCancel
        self.onCreate = onCreate
        _model = State(initialValue: SequenceConfigModel(artifact: artifact, initial: initial))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .entryPoint:
                    entryPointForm
                case .resolveInterfaces:
                    resolveInterfacesForm
                }
            }
            #if os(macOS)
            .frame(maxWidth: 460)
            #endif
            .navigationTitle(model.step == .entryPoint ? "New Sequence Diagram" : "Resolve Interfaces")
            .toolbar {
                if model.step == .resolveInterfaces {
                    ToolbarItem(placement: .navigation) {
                        Button(.app("View.SequenceConfigSheet.Back")) { model.back() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.SequenceConfigSheet.Cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch model.step {
                    case .entryPoint:
                        Button(.app("View.SequenceConfigSheet.Next"), action: advance)
                            .keyboardShortcut(.confirmDialog)
                            .disabled(!model.canAdvance)
                            .accessibilityIdentifier("sequenceConfig.nextButton")
                    case .resolveInterfaces:
                        Button(.app("View.SequenceConfigSheet.Create")) { onCreate(model.configuration) }
                            .keyboardShortcut(.confirmDialog)
                            .accessibilityIdentifier("sequenceConfig.createButton")
                    }
                }
            }
        }
    }

    // MARK: - Phase 1: entry point

    private var entryPointForm: some View {
        Form {
            Section {
                Text(.app("View.SequenceConfigSheet.ChooseWhereTraceBegins"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $typeQuery)
                        Picker(.app("View.SequenceConfigSheet.Type"), selection: entryTypeName) {
                            Text(localized: model.freeFunctionNames.isEmpty
                                ? .app("View.SequenceConfigSheet.SelectEllipsis")
                                : .app("View.SequenceConfigSheet.NoneTopLevelFunctions")).tag("")
                            ForEach(model.callableTypeNames.filtered(by: typeQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("sequenceConfig.typePicker")
                    }
                } label: {
                    Text(.app("View.SequenceConfigSheet.Type"))
                }

                LabeledContent(model.entryTypeName.isEmpty ? "Function" : "Method") {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        PickerFilterField(text: $methodQuery)
                        Picker(.app("View.SequenceConfigSheet.Method"), selection: $model.entryMethodName) {
                            Text(.app("View.SequenceConfigSheet.Select")).tag("")
                            ForEach(model.methodNames.filtered(by: methodQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(model.methodNames.isEmpty)
                        .accessibilityIdentifier("sequenceConfig.methodPicker")
                    }
                }

                LabeledContent {
                    Stepper(value: $model.maxDepth, in: 1...20) {
                        Text(model.maxDepth, format: .number)
                    }
                } label: {
                    Text(.app("View.SequenceConfigSheet.MaxDepth"))
                }
            }
        }
    }

    /// The entry-type picker goes through `selectEntryType` rather than the stored property, so a
    /// scope change takes the method selection with it.
    private var entryTypeName: Binding<String> {
        Binding(get: { model.entryTypeName }, set: { model.selectEntryType($0) })
    }

    // MARK: - Phase 2: interface resolution

    @ViewBuilder
    private var resolveInterfacesForm: some View {
        Form {
            Section {
                Text(.app("View.SequenceConfigSheet.TheseAbstractionsAppearAlong"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(model.mappings) { mapping in
                    LabeledContent(mapping.protocolName) {
                        Picker(mapping.protocolName, selection: selection(for: mapping.id)) {
                            Text(.app("View.SequenceConfigSheet.LeaveAbstract")).tag(String?.none)
                            ForEach(mapping.candidates, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private func selection(for protocolName: String) -> Binding<String?> {
        Binding(
            get: { model.mappings.first { $0.id == protocolName }?.selection },
            set: { model.select($0, forAbstractionNamed: protocolName) }
        )
    }

    // MARK: - Actions

    private func advance() {
        if case .finished(let configuration) = model.advance() {
            onCreate(configuration)
        }
    }
}
