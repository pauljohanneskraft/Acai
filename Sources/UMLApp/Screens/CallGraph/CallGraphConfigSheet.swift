import SwiftUI
import UMLCore
import UMLDiagram

/// Configuration popup for a static call graph: pick the **scope** that bounds which methods are
/// treated as callers — the whole codebase, a single type, or one build module. Resolved callees
/// outside the scope still appear as leaf nodes.
struct CallGraphConfigSheet: View {
    let artifact: CodeArtifact
    /// Pre-fills the form when re-configuring an existing diagram.
    let initial: CallGraphScope
    let onCancel: () -> Void
    let onCreate: (CallGraphScope) -> Void

    @State private var scope: CallGraphScope

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
            Text("New Call Graph")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a scope. Every method (and free function) in scope becomes a caller; "
                     + "each statically-resolvable call is an edge. A narrower scope keeps large "
                     + "codebases legible — calls out of scope still show their target as a leaf.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Scope") {
                    Picker("Scope", selection: $scope) {
                        Text("Whole Codebase").tag(CallGraphScope.wholeCodebase)
                        if !moduleNames.isEmpty {
                            Section("Modules") {
                                ForEach(moduleNames, id: \.self) { name in
                                    Text(name).tag(CallGraphScope.module(name))
                                }
                            }
                        }
                        Section("Types") {
                            ForEach(typeNames, id: \.self) { name in
                                Text(name).tag(CallGraphScope.type(name))
                            }
                        }
                    }
                    .labelsHidden()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { onCreate(scope) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Lookups

    /// Simple names of every type that declares at least one method (potential callers/callees).
    private var typeNames: [String] {
        artifact.types
            .filter { type in type.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    /// Build modules present in the codebase, derived from each type's file path.
    private var moduleNames: [String] {
        artifact.types
            .map { BuildProduct.productName(forFilePath: $0.location?.filePath ?? "") }
            .uniqued()
            .sorted()
    }
}
