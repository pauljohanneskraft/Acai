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
        let initialType = initial?.entryTypeName ?? ""
        let initialMethod = initial?.entryMethodName ?? ""
        // A saved free-function entry stores an empty type name; reselect the group so re-editing
        // shows the right picker state.
        let isFreeFunctionEntry = initialType.isEmpty && !initialMethod.isEmpty
            && artifact.freestandingFunctions.contains { $0.name == initialMethod }
        _entryTypeName = State(initialValue: isFreeFunctionEntry ? Self.freeFunctionGroup : initialType)
        _entryMethodName = State(initialValue: initialMethod)
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
                Picker("Type", selection: $entryTypeName) {
                    Text("Select…").tag("")
                    ForEach(callableTypeNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .onChange(of: entryTypeName) { _, _ in
                    if !methodNames.contains(entryMethodName) {
                        entryMethodName = methodNames.first ?? ""
                    }
                }
            }

            LabeledContent("Method") {
                Picker("Method", selection: $entryMethodName) {
                    Text("Select…").tag("")
                    ForEach(methodNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(entryTypeName.isEmpty)
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
                    .disabled(entryTypeName.isEmpty || entryMethodName.isEmpty)
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
        let preview = artifact.sequenceDiagram(
            entryPoint: (resolvedEntryTypeName, entryMethodName),
            maxDepth: maxDepth
        )
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
            entryTypeName: resolvedEntryTypeName,
            entryMethodName: entryMethodName,
            maxDepth: maxDepth,
            typeMapping: mapping
        ))
    }

    // MARK: - Lookups

    /// Pseudo-"type" group that lists the codebase's top-level (free) functions as entry points.
    /// Maps to an empty entry-type name, which `sequenceDiagram(entryPoint:)` resolves against
    /// `freestandingFunctions`.
    static let freeFunctionGroup = "⟨Top-Level Functions⟩"

    /// The entry-type name passed to the engine: the free-function group resolves to an empty
    /// string (the core's signal for a top-level-function entry point).
    private var resolvedEntryTypeName: String {
        entryTypeName == Self.freeFunctionGroup ? "" : entryTypeName
    }

    private var freeFunctionNames: [String] {
        artifact.freestandingFunctions.map(\.name).uniqued().sorted()
    }

    /// Names of types that declare at least one method — valid entry-point types. The top-level
    /// functions group is offered first when the codebase has any free functions.
    private var callableTypeNames: [String] {
        let typeNames = artifact.types
            .filter { $0.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
        return freeFunctionNames.isEmpty ? typeNames : [Self.freeFunctionGroup] + typeNames
    }

    /// Method names on the currently selected entry type, or the top-level functions when the
    /// free-function group is selected.
    private var methodNames: [String] {
        if entryTypeName == Self.freeFunctionGroup { return freeFunctionNames }
        guard let type = artifact.types.first(where: { $0.name == entryTypeName }) else { return [] }
        return type.members
            .filter { $0.kind == .method }
            .map(\.name)
            .uniqued()
            .sorted()
    }

}

private extension Sequence where Element: Hashable {
    /// Order-preserving de-duplication.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
