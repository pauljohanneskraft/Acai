import SwiftUI
import AcaiCore
import AcaiDiagram

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
    @State private var scopeQuery = ""
    @State private var variableQuery = ""

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
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $scopeQuery)
                        Picker("Scope", selection: $scope) {
                            Text("Select…").tag(Scope?.none)
                            if !artifact.globalVariables.isEmpty {
                                Text("Global Variables").tag(Scope?.some(.globals))
                            }
                            ForEach(typeNamesWithStoredProperties.filtered(by: scopeQuery), id: \.self) { name in
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
                }

                LabeledContent("Variable") {
                    VStack(alignment: .leading, spacing: 4) {
                        PickerFilterField(text: $variableQuery)
                        Picker("Variable", selection: $variableName) {
                            Text("Select…").tag("")
                            ForEach(variableNames.filtered(by: variableQuery), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(scope == nil)
                    }
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
        .frame(maxWidth: 460)
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

    /// Every type declaration (including nested ones) that declares at least one
    /// stored property. Mirrors `StateAnalysis.findType`, which recurses into
    /// `nestedTypes` and matches on `qualifiedName`.
    private var typesWithStoredProperties: [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.members.contains(where: { $0.kind == .property && !$0.isComputed }) {
                    result.append(type)
                }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return result
    }

    /// Qualified names of types that declare at least one stored property.
    /// Qualified (not simple) names so nested types are reachable and same-named
    /// types don't collide.
    private var typeNamesWithStoredProperties: [String] {
        typesWithStoredProperties.map(\.qualifiedName).uniqued().sorted()
    }

    /// Variables in the selected scope: plausible state holders (enum-typed or
    /// bool/int/string) first, then the rest, each group alphabetical.
    private var variableNames: [String] {
        let members: [Member]
        switch scope {
        case .type(let qualifiedName):
            members = typesWithStoredProperties.first { $0.qualifiedName == qualifiedName }?
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
