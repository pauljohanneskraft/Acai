import SwiftUI
import UMLCore
import UMLDiagram

/// Configuration popup for a value-flow state diagram: pick the variable whose
/// assignments define the state space (a stored property of a type, or a global),
/// plus the maximum number of distinct states before the analysis fails.
struct StateConfigSheet: View {
    let artifact: CodeArtifact
    /// Pre-fills the form when editing an existing diagram's configuration.
    let initial: StateDiagramConfiguration?
    let onCancel: () -> Void
    let onCreate: (StateDiagramConfiguration) -> Void

    /// Where the variable lives: a type, or the module/global scope.
    private enum Scope: Hashable {
        case type(String)
        case globals
    }

    @State private var scope: Scope?
    @State private var variableName: String
    @State private var maxStates: Int

    init(
        artifact: CodeArtifact,
        initial: StateDiagramConfiguration? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (StateDiagramConfiguration) -> Void
    ) {
        self.artifact = artifact
        self.initial = initial
        self.onCancel = onCancel
        self.onCreate = onCreate
        if let initial {
            _scope = State(initialValue: initial.typeName.map(Scope.type) ?? .globals)
        } else {
            _scope = State(initialValue: nil)
        }
        _variableName = State(initialValue: initial?.variableName ?? "")
        _maxStates = State(initialValue: initial?.maxStates ?? 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New State Diagram")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a variable. Its possible values (\"states\") are inferred from "
                     + "assignments across the codebase; values that can't be enumerated "
                     + "statically make the analysis fail with an explanation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Scope") {
                    Picker("Scope", selection: $scope) {
                        Text("Select…").tag(Scope?.none)
                        if !artifact.globalVariables.isEmpty {
                            Text("Global Variables").tag(Scope?.some(.globals))
                        }
                        ForEach(typeNamesWithStoredProperties, id: \.self) { name in
                            Text(name).tag(Scope?.some(.type(name)))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: scope) { _, _ in
                        if !variableNames.contains(variableName) {
                            variableName = variableNames.first ?? ""
                        }
                    }
                }

                LabeledContent("Variable") {
                    Picker("Variable", selection: $variableName) {
                        Text("Select…").tag("")
                        ForEach(variableNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(scope == nil)
                }

                LabeledContent("Max states") {
                    Stepper(value: $maxStates, in: 5...100, step: 5) {
                        Text("\(maxStates)")
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(scope == nil || variableName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func create() {
        let typeName: String? = if case .type(let name) = scope { name } else { nil }
        onCreate(StateDiagramConfiguration(
            typeName: typeName,
            variableName: variableName,
            maxStates: maxStates
        ))
    }

    // MARK: - Lookups

    /// Names of types that declare at least one stored property.
    private var typeNamesWithStoredProperties: [String] {
        artifact.types
            .filter { type in type.members.contains { $0.kind == .property && !$0.isComputed } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    /// Variables in the selected scope: plausible state holders (enum-typed or
    /// bool/int/string) first, then the rest, each group alphabetical.
    private var variableNames: [String] {
        let members: [Member]
        switch scope {
        case .type(let name):
            members = artifact.types.first { $0.name == name }?
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

    /// Whether a variable's declared type suggests an enumerable state space.
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
}

private extension Sequence where Element: Hashable {
    /// Order-preserving de-duplication.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
