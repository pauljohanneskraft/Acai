import SwiftUI
import AcaiCore

// MARK: - Member Editing (properties & methods on `.type` nodes)

extension FreeformDiagramInspector {
    @ViewBuilder
    func memberSheetContent(_ sheet: MemberSheet) -> some View {
        switch sheet {
        case .addProperty(let nodeID):
            PropertyEditorSheet(existing: nil) { draft in
                viewModel.members.addProperty(to: nodeID, draft: draft)
            }
        case .editProperty(let nodeID, let memberID):
            PropertyEditorSheet(existing: property(nodeID: nodeID, memberID: memberID)) { draft in
                viewModel.members.updateProperty(in: nodeID, memberID: memberID, draft: draft)
            }
        case .addMethod(let nodeID):
            MethodEditorSheet(existing: nil) { draft in
                viewModel.members.addMethod(to: nodeID, draft: draft)
            }
        case .editMethod(let nodeID, let memberID):
            MethodEditorSheet(existing: method(nodeID: nodeID, memberID: memberID)) { draft in
                viewModel.members.updateMethod(in: nodeID, memberID: memberID, draft: draft)
            }
        }
    }

    private func property(nodeID: String, memberID: UUID) -> FreeformDiagram.Node.Member? {
        guard let node = viewModel.nodes.first(where: { $0.id == nodeID }),
              case .type(let content) = node.content else { return nil }
        return content.properties.first { $0.id == memberID }
    }

    private func method(nodeID: String, memberID: UUID) -> FreeformDiagram.Node.Member? {
        guard let node = viewModel.nodes.first(where: { $0.id == nodeID }),
              case .type(let content) = node.content else { return nil }
        return content.methods.first { $0.id == memberID }
    }

    // MARK: - Properties

    func propertiesSection(nodeID: String, content: FreeformDiagram.Node.TypeContent) -> some View {
        Section {
            ForEach(content.properties) { prop in
                propertyRow(nodeID: nodeID, prop: prop)
            }
            addPropertyRow(nodeID: nodeID)
        } header: {
            Text(.app("View.FreeformDiagramInspector.Properties"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func propertyRow(nodeID: String, prop: FreeformDiagram.Node.Member) -> some View {
        HStack {
            Text(verbatim: prop.displayString)
                .font(.system(size: 12, design: .monospaced))
                .contentShape(Rectangle())
                .onTapGesture {
                    memberSheet = .editProperty(nodeID: nodeID, memberID: prop.id)
                }
            Spacer()
            Button(role: .destructive) {
                viewModel.members.removeProperty(from: nodeID, memberID: prop.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("inspector.removePropertyButton.\(prop.id)")
        }
        .accessibilityIdentifier("inspector.propertyRow.\(prop.id)")
    }

    private func addPropertyRow(nodeID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $newPropertyName) {
                Text(.app("View.FreeformDiagramInspector.MemberName"))
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .newProperty)
            .accessibilityIdentifier("inspector.newPropertyNameField")
            TextField(text: $newPropertyType) {
                Text(.app("View.FreeformDiagramInspector.Type"))
            }
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("inspector.newPropertyTypeField")
            MemberFlagsFields(
                accessLevel: $newPropertyAccessLevel, isStatic: $newPropertyIsStatic,
                isAbstract: $newPropertyIsAbstract
            )
            Button {
                viewModel.members.addProperty(to: nodeID, draft: .init(
                    name: newPropertyName, type: newPropertyType, accessLevel: newPropertyAccessLevel,
                    isStatic: newPropertyIsStatic, isAbstract: newPropertyIsAbstract
                ))
                newPropertyName = ""
                newPropertyType = ""
                newPropertyAccessLevel = .internal
                newPropertyIsStatic = false
                newPropertyIsAbstract = false
            } label: {
                Label(.app("View.FreeformDiagramInspector.AddProperty"), systemImage: "plus.circle")
            }
            .disabled(newPropertyName.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("inspector.addPropertyButton")
        }
    }

    // MARK: - Methods

    func methodsSection(nodeID: String, content: FreeformDiagram.Node.TypeContent) -> some View {
        Section {
            ForEach(content.methods) { method in
                methodRow(nodeID: nodeID, method: method)
            }
            addMethodRow(nodeID: nodeID)
        } header: {
            Text(.app("View.FreeformDiagramInspector.Methods"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func methodRow(nodeID: String, method: FreeformDiagram.Node.Member) -> some View {
        HStack {
            Text(verbatim: method.displayString)
                .font(.system(size: 12, design: .monospaced))
                .contentShape(Rectangle())
                .onTapGesture {
                    memberSheet = .editMethod(nodeID: nodeID, memberID: method.id)
                }
            Spacer()
            Button(role: .destructive) {
                viewModel.members.removeMethod(from: nodeID, memberID: method.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("inspector.removeMethodButton.\(method.id)")
        }
        .accessibilityIdentifier("inspector.methodRow.\(method.id)")
    }

    private func addMethodRow(nodeID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $newMethodName) {
                Text(.app("View.FreeformDiagramInspector.MemberName"))
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .newMethod)
            .accessibilityIdentifier("inspector.newMethodNameField")
            TextField(text: $newMethodReturnType) {
                Text(.app("View.FreeformDiagramInspector.ReturnType"))
            }
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("inspector.newMethodReturnTypeField")
            MemberFlagsFields(
                accessLevel: $newMethodAccessLevel, isStatic: $newMethodIsStatic,
                isAbstract: $newMethodIsAbstract
            )
            ParameterListEditor(parameters: $newMethodParameters, accessibilityPrefix: "inspector.newMethod")
            Button {
                viewModel.members.addMethod(to: nodeID, draft: .init(
                    name: newMethodName, type: newMethodReturnType, accessLevel: newMethodAccessLevel,
                    isStatic: newMethodIsStatic, isAbstract: newMethodIsAbstract,
                    structuredParameters: newMethodParameters
                ))
                newMethodName = ""
                newMethodReturnType = ""
                newMethodParameters = []
                newMethodAccessLevel = .internal
                newMethodIsStatic = false
                newMethodIsAbstract = false
            } label: {
                Label(.app("View.FreeformDiagramInspector.AddMethod"), systemImage: "plus.circle")
            }
            .disabled(newMethodName.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("inspector.addMethodButton")
        }
    }
}
