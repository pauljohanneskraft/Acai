import SwiftUI
import AcaiCore
import AcaiDiagram

/// Two-phase configuration popup for a sequence diagram.
///
/// 1. **Entry point** — pick the starting type and method, and a maximum call depth.
/// 2. **Interface resolution** — a first-pass trace runs, then a concrete-type dropdown is
///    offered for each protocol/interface actually encountered (and that has a conformer), so
///    the diagram can follow real implementations instead of stopping at an abstraction.
struct SequenceConfigSheet: View {
    let artifact: CodeArtifact
    /// Pre-fills the form when editing an existing diagram's configuration.
    let initial: SequenceDiagramConfiguration?
    let onCancel: () -> Void
    let onCreate: (SequenceDiagramConfiguration) -> Void

    @State private var entryTypeName: String
    @State private var entryMethodName: String
    @State private var maxDepth: Int
    @State private var phase: Phase = .entryPoint
    @State private var mappingRows: [MappingRow] = []
    @State private var typeQuery = ""
    @State private var methodQuery = ""

    private enum Phase { case entryPoint, resolveInterfaces }

    private struct MappingRow: Identifiable {
        let id: String
        var protocolName: String { id }
        let candidates: [String]
        var selection: String?  // chosen concrete type, or nil = leave abstract
    }

    init(
        artifact: CodeArtifact,
        initial: SequenceDiagramConfiguration? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (SequenceDiagramConfiguration) -> Void
    ) {
        self.artifact = artifact
        self.initial = initial
        self.onCancel = onCancel
        self.onCreate = onCreate
        // An empty entry-type name is the top-level (no class) scope — it round-trips directly, so
        // re-editing a free-function entry restores the right picker state with no translation.
        _entryTypeName = State(initialValue: initial?.entryTypeName ?? "")
        _entryMethodName = State(initialValue: initial?.entryMethodName ?? "")
        _maxDepth = State(initialValue: initial?.maxDepth ?? 5)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .entryPoint:
                    entryPointForm
                case .resolveInterfaces:
                    resolveInterfacesForm
                }
            }
            #if os(macOS)
            .frame(maxWidth: 460)
            #endif
            .navigationTitle(phase == .entryPoint ? "New Sequence Diagram" : "Resolve Interfaces")
            .toolbar {
                if phase == .resolveInterfaces {
                    ToolbarItem(placement: .navigation) {
                        Button(.app("View.SequenceConfigSheet.Back")) { phase = .entryPoint }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.SequenceConfigSheet.Cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch phase {
                    case .entryPoint:
                        Button(.app("View.SequenceConfigSheet.Next"), action: advance)
                            .keyboardShortcut(.defaultAction)
                            .disabled(entryMethodName.isEmpty)
                            .accessibilityIdentifier("sequenceConfig.nextButton")
                    case .resolveInterfaces:
                        Button(.app("View.SequenceConfigSheet.Create"), action: create)
                            .keyboardShortcut(.defaultAction)
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
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $typeQuery)
                        Picker(.app("View.SequenceConfigSheet.Type"), selection: $entryTypeName) {
                            Text(localized: freeFunctionNames.isEmpty
                                ? .app("View.SequenceConfigSheet.SelectEllipsis")
                                : .app("View.SequenceConfigSheet.NoneTopLevelFunctions")).tag("")
                            ForEach(callableTypeNames.filtered(by: typeQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("sequenceConfig.typePicker")
                        .onChange(of: entryTypeName) { _, _ in
                            if !methodNames.contains(entryMethodName) {
                                entryMethodName = methodNames.first ?? ""
                            }
                        }
                    }
                } label: {
                    Text(.app("View.SequenceConfigSheet.Type"))
                }

                LabeledContent(entryTypeName.isEmpty ? "Function" : "Method") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $methodQuery)
                        Picker(.app("View.SequenceConfigSheet.Method"), selection: $entryMethodName) {
                            Text(.app("View.SequenceConfigSheet.Select")).tag("")
                            ForEach(methodNames.filtered(by: methodQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(methodNames.isEmpty)
                        .accessibilityIdentifier("sequenceConfig.methodPicker")
                    }
                }

                LabeledContent {
                    Stepper(value: $maxDepth, in: 1...20) {
                        Text(maxDepth, format: .number)
                    }
                } label: {
                    Text(.app("View.SequenceConfigSheet.MaxDepth"))
                }
            }
        }
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
                ForEach($mappingRows) { $row in
                    LabeledContent(row.protocolName) {
                        Picker(row.protocolName, selection: $row.selection) {
                            Text(.app("View.SequenceConfigSheet.LeaveAbstract")).tag(String?.none)
                            ForEach(row.candidates, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        let preview = SequenceDiagramBuilder(
            entryPoint: (entryTypeName, entryMethodName),
            maxDepth: maxDepth
        ).build(from: artifact)
        var rows: [MappingRow] = []
        var seen: Set<String> = []
        for participant in preview.participants where !seen.contains(participant.name) {
            seen.insert(participant.name)
            // Resolves existential spellings (`any P`) too; the mapping key stays the raw
            // participant name because the generator substitutes receiver strings verbatim.
            let candidates = artifact.conformerNames(ofAbstractionNamed: participant.name)
            guard !candidates.isEmpty else { continue }
            rows.append(MappingRow(
                id: participant.name,
                candidates: candidates,
                selection: initial?.typeMapping[participant.name]
            ))
        }

        if rows.isEmpty {
            create()
        } else {
            mappingRows = rows
            phase = .resolveInterfaces
        }
    }

    private func create() {
        var mapping: [String: String] = [:]
        for row in mappingRows {
            if let concrete = row.selection { mapping[row.protocolName] = concrete }
        }
        onCreate(SequenceDiagramConfiguration(
            entryTypeName: entryTypeName,
            entryMethodName: entryMethodName,
            maxDepth: maxDepth,
            typeMapping: mapping
        ))
    }

    // MARK: - Lookups

    /// The codebase's top-level (free) functions — the entry points available when no class is
    /// selected (an empty entry-type name, which `sequenceDiagram(entryPoint:)` resolves against
    /// `freestandingFunctions`).
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

    private var methodNames: [String] {
        guard !entryTypeName.isEmpty else { return freeFunctionNames }
        guard let type = artifact.types.first(where: { $0.name == entryTypeName }) else { return [] }
        return type.members
            .filter { $0.kind == .method }
            .map(\.name)
            .uniqued()
            .sorted()
    }

}
