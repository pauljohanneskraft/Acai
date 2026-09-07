import SwiftUI
import AcaiCore
import AcaiDiagram

/// Configuration popup for a value-flow state diagram: pick the variable whose assignments
/// define the state space, plus the max number of distinct states before analysis fails.
struct StateConfigSheet: View {
    let artifact: CodeArtifact
    let initial: StateDiagramConfiguration?
    let onCancel: () -> Void
    let onCreate: (StateDiagramConfiguration) -> Void

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
        NavigationStack {
            Form {
                Section {
                    Text(.app("View.StateConfigSheet.PickVariablePossibleValues"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent {
                        VStack(alignment: .leading, spacing: 4) {
                            PickerFilterField(text: $scopeQuery)
                            Picker(.app("View.StateConfigSheet.Scope"), selection: $scope) {
                                Text(.app("View.StateConfigSheet.Select")).tag(Scope?.none)
                                if !artifact.globalVariables.isEmpty {
                                    Text(.app("View.StateConfigSheet.GlobalVariables")).tag(Scope?.some(.globals))
                                }
                                ForEach(typeNamesWithStoredProperties.filtered(by: scopeQuery), id: \.self) { name in
                                    Text(verbatim: name).tag(Scope?.some(.type(name)))
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("stateConfig.scopePicker")
                            .onChange(of: scope) { _, _ in
                                if !variableNames.contains(variableName) {
                                    variableName = variableNames.first ?? ""
                                }
                            }
                        }
                    } label: {
                        Text(.app("View.StateConfigSheet.Scope"))
                    }

                    LabeledContent {
                        VStack(alignment: .leading, spacing: 4) {
                            PickerFilterField(text: $variableQuery)
                            Picker(.app("View.StateConfigSheet.Variable"), selection: $variableName) {
                                Text(.app("View.StateConfigSheet.Select")).tag("")
                                ForEach(variableNames.filtered(by: variableQuery), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                            }
                            .labelsHidden()
                            .disabled(scope == nil)
                            .accessibilityIdentifier("stateConfig.variablePicker")
                        }
                    } label: {
                        Text(.app("View.StateConfigSheet.Variable"))
                    }

                    LabeledContent {
                        Stepper(value: $maxStates, in: 5...100, step: 5) {
                            Text(maxStates, format: .number)
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
                    Button(.app("View.StateConfigSheet.Create"), action: create)
                        .keyboardShortcut(.defaultAction)
                        .disabled(scope == nil || variableName.isEmpty)
                        .accessibilityIdentifier("stateConfig.createButton")
                }
            }
        }
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

    /// Mirrors `StateAnalysis.findType`, which recurses into `nestedTypes` and matches on
    /// `qualifiedName`.
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

    /// Qualified (not simple) names so nested types are reachable and same-named types don't
    /// collide.
    private var typeNamesWithStoredProperties: [String] {
        typesWithStoredProperties.map(\.qualifiedName).uniqued().sorted()
    }

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
