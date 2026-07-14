import SwiftUI
import UMLCore
import UMLDiagram

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
        let id: String  // protocol name
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
        VStack(alignment: .leading, spacing: 16) {
            Text(phase == .entryPoint ? "New Sequence Diagram" : "Resolve Interfaces")
                .font(.title2.bold())

            switch phase {
            case .entryPoint:
                entryPointForm
            case .resolveInterfaces:
                resolveInterfacesForm
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Phase 1: entry point

    private var entryPointForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose where the trace begins. Calls are followed through explicitly-typed "
                 + "property receivers.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LabeledContent("Type") {
                VStack(alignment: .leading, spacing: 4) {
                    PickerFilterField(text: $typeQuery)
                    Picker("Type", selection: $entryTypeName) {
                        // No class selected = top-level scope; the method picker then lists free functions.
                        Text(freeFunctionNames.isEmpty ? "Select…" : "None (top-level functions)").tag("")
                        ForEach(callableTypeNames.filtered(by: typeQuery), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: entryTypeName) { _, _ in
                        if !methodNames.contains(entryMethodName) {
                            entryMethodName = methodNames.first ?? ""
                        }
                    }
                }
            }

            LabeledContent(entryTypeName.isEmpty ? "Function" : "Method") {
                VStack(alignment: .leading, spacing: 4) {
                    PickerFilterField(text: $methodQuery)
                    Picker("Method", selection: $entryMethodName) {
                        Text("Select…").tag("")
                        ForEach(methodNames.filtered(by: methodQuery), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(methodNames.isEmpty)
                }
            }

            LabeledContent("Max depth") {
                Stepper(value: $maxDepth, in: 1...20) {
                    Text("\(maxDepth)")
                }
            }
        }
    }

    // MARK: - Phase 2: interface resolution

    @ViewBuilder
    private var resolveInterfacesForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These abstractions appear along the call path. Pick a concrete type to follow "
                 + "its implementation, or leave it abstract.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach($mappingRows) { $row in
                LabeledContent(row.protocolName) {
                    Picker(row.protocolName, selection: $row.selection) {
                        Text("Leave abstract").tag(String?.none)
                        ForEach(row.candidates, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if phase == .resolveInterfaces {
                Button("Back") { phase = .entryPoint }
            }
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            switch phase {
            case .entryPoint:
                Button("Next", action: advance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(entryMethodName.isEmpty)
            case .resolveInterfaces:
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    /// Run a first-pass trace; if any encountered participant is an abstraction with conformers,
    /// move to the resolution phase, otherwise create immediately.
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

    /// Names of types that declare at least one method — valid entry-point types.
    private var callableTypeNames: [String] {
        artifact.types
            .filter { $0.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    /// Method names on the selected entry type, or the top-level functions when no class is
    /// selected (empty type name).
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
