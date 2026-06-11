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
    let initial: GeneratedDiagram.SequenceConfiguration?
    let onCancel: () -> Void
    let onCreate: (GeneratedDiagram.SequenceConfiguration) -> Void

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
        initial: GeneratedDiagram.SequenceConfiguration? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (GeneratedDiagram.SequenceConfiguration) -> Void
    ) {
        self.artifact = artifact
        self.initial = initial
        self.onCancel = onCancel
        self.onCreate = onCreate
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
            entryPoint: (entryTypeName, entryMethodName),
            maxDepth: maxDepth
        )
        var rows: [MappingRow] = []
        var seen: Set<String> = []
        for participant in preview.participants where !seen.contains(participant.name) {
            seen.insert(participant.name)
            guard isAbstraction(participant.name) else { continue }
            let candidates = conformerNames(ofTypeNamed: participant.name)
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
        onCreate(GeneratedDiagram.SequenceConfiguration(
            entryTypeName: entryTypeName,
            entryMethodName: entryMethodName,
            maxDepth: maxDepth,
            typeMapping: mapping
        ))
    }

    // MARK: - Lookups

    /// Names of types that declare at least one method — valid entry-point types.
    private var callableTypeNames: [String] {
        artifact.types
            .filter { $0.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    /// Method names on the currently selected entry type.
    private var methodNames: [String] {
        guard let type = artifact.types.first(where: { $0.name == entryTypeName }) else { return [] }
        return type.members
            .filter { $0.kind == .method }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    private func isAbstraction(_ typeName: String) -> Bool {
        guard let type = artifact.types.first(where: { $0.name == typeName }) else { return false }
        return type.kind == .protocol || type.kind == .interface
    }

    /// Concrete types that conform to / inherit from the named type, found via relationship
    /// edges (target = the abstraction's id). Relationships are id-based after enrichment.
    private func conformerNames(ofTypeNamed typeName: String) -> [String] {
        guard let type = artifact.types.first(where: { $0.name == typeName }) else { return [] }
        let conformerIDs = artifact.relationships
            .filter { $0.target == type.id && ($0.kind == .conformance || $0.kind == .inheritance) }
            .map(\.source)
        return conformerIDs
            .compactMap { id in artifact.types.first(where: { $0.id == id })?.name }
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
