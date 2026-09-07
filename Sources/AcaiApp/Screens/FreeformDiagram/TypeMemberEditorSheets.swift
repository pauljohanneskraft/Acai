import SwiftUI
import AcaiCore

// MARK: - Member Editor Sheets
//
// Structured property/method editors presented as sheets when an inspector row is tapped
// (pre-filled) or the properties/methods section's "Add" row is used (blank). Save commits
// through `TypeMemberEditor`'s `add*`/`update*` mutators; Cancel discards the local draft.

struct PropertyEditorSheet: View {
    let existing: FreeformDiagram.Node.Member?
    let onSave: (FreeformDiagram.Node.Member) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FreeformDiagram.Node.Member

    init(existing: FreeformDiagram.Node.Member?, onSave: @escaping (FreeformDiagram.Node.Member) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _draft = State(initialValue: existing ?? FreeformDiagram.Node.Member(name: ""))
    }

    private var isNameEmpty: Bool { draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft.name) {
                        Text(.app("View.PropertyEditorSheet.Name"))
                    }
                    .accessibilityIdentifier("memberEditor.property.nameField")
                    TextField(text: $draft.type) {
                        Text(.app("View.PropertyEditorSheet.Type"))
                    }
                    .accessibilityIdentifier("memberEditor.property.typeField")
                }
                MemberFlagsSection(
                    accessLevel: $draft.accessLevel, isStatic: $draft.isStatic, isAbstract: $draft.isAbstract
                )
            }
            .navigationTitle(existing == nil ? "Add Property" : "Edit Property")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.PropertyEditorSheet.Cancel")) { dismiss() }
                        .accessibilityIdentifier("memberEditor.property.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.PropertyEditorSheet.Save")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(isNameEmpty)
                    .accessibilityIdentifier("memberEditor.property.saveButton")
                }
            }
        }
    }
}

struct MethodEditorSheet: View {
    let existing: FreeformDiagram.Node.Member?
    let onSave: (FreeformDiagram.Node.Member) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FreeformDiagram.Node.Member

    init(existing: FreeformDiagram.Node.Member?, onSave: @escaping (FreeformDiagram.Node.Member) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _draft = State(initialValue: existing ?? FreeformDiagram.Node.Member(name: ""))
    }

    private var isNameEmpty: Bool { draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft.name) {
                        Text(.app("View.MethodEditorSheet.Name"))
                    }
                    .accessibilityIdentifier("memberEditor.method.nameField")
                    TextField(text: $draft.type) {
                        Text(.app("View.MethodEditorSheet.ReturnType"))
                    }
                    .accessibilityIdentifier("memberEditor.method.returnTypeField")
                }
                MemberFlagsSection(
                    accessLevel: $draft.accessLevel, isStatic: $draft.isStatic, isAbstract: $draft.isAbstract
                )
                Section {
                    ParameterListEditor(
                        parameters: $draft.structuredParameters, accessibilityPrefix: "memberEditor.method"
                    )
                } header: {
                    Text(.app("View.MethodEditorSheet.Parameters"))
                }
            }
            .navigationTitle(existing == nil ? "Add Method" : "Edit Method")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.MethodEditorSheet.Cancel")) { dismiss() }
                        .accessibilityIdentifier("memberEditor.method.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.MethodEditorSheet.Save")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(isNameEmpty)
                    .accessibilityIdentifier("memberEditor.method.saveButton")
                }
            }
        }
    }
}

/// Used by both member editor sheets and the inline add-property/add-method rows.
struct MemberFlagsFields: View {
    @Binding var accessLevel: AccessLevel
    @Binding var isStatic: Bool
    @Binding var isAbstract: Bool

    var body: some View {
        Picker(.app("View.MemberFlagsFields.AccessLevel"), selection: $accessLevel) {
            ForEach(AccessLevel.allCases, id: \.self) { level in
                Text(verbatim: level.rawValue.capitalized).tag(level)
            }
        }
        .accessibilityIdentifier("memberEditor.accessLevelPicker")
        Toggle(.app("View.MemberFlagsFields.Static"), isOn: $isStatic)
            .accessibilityIdentifier("memberEditor.staticToggle")
        Toggle(.app("View.MemberFlagsFields.Abstract"), isOn: $isAbstract)
            .accessibilityIdentifier("memberEditor.abstractToggle")
    }
}

struct MemberFlagsSection: View {
    @Binding var accessLevel: AccessLevel
    @Binding var isStatic: Bool
    @Binding var isAbstract: Bool

    var body: some View {
        Section {
            MemberFlagsFields(accessLevel: $accessLevel, isStatic: $isStatic, isAbstract: $isAbstract)
        }
    }
}

/// Shared by the method editor sheet and the inline add-method row.
struct ParameterListEditor: View {
    @Binding var parameters: [FreeformDiagram.Node.Parameter]
    let accessibilityPrefix: String

    var body: some View {
        ForEach(parameters.indices, id: \.self) { index in
            HStack {
                TextField(text: Binding(
                    get: { parameters[index].name },
                    set: { parameters[index].name = $0 }
                )) {
                    Text(.app("View.ParameterListEditor.Name"))
                }
                .accessibilityIdentifier("\(accessibilityPrefix).parameterNameField.\(index)")
                TextField(text: Binding(
                    get: { parameters[index].type },
                    set: { parameters[index].type = $0 }
                )) {
                    Text(.app("View.ParameterListEditor.Type"))
                }
                .accessibilityIdentifier("\(accessibilityPrefix).parameterTypeField.\(index)")
                Button(role: .destructive) {
                    parameters.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("\(accessibilityPrefix).removeParameterButton.\(index)")
            }
        }
        Button {
            parameters.append(.init(name: "", type: ""))
        } label: {
            Label(.app("View.ParameterListEditor.AddParameter"), systemImage: "plus.circle")
        }
        .accessibilityIdentifier("\(accessibilityPrefix).addParameterButton")
    }
}
