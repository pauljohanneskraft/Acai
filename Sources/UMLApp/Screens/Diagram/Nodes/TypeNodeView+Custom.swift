import SwiftUI
import UMLCore
import UMLRender

// MARK: - Custom-diagram convenience initializer
//
// `TypeNodeView` lives in `UMLRender` (shared with the CLI image renderer), but custom
// diagrams are an app-only concept, so this initializer stays here and delegates to the
// shared view's primitive initializer.
extension TypeNodeView {
    /// Create from a custom diagram node with type content.
    init(node: CustomDiagram.Node, content: CustomDiagram.Node.TypeContent, isSelected: Bool) {
        self.init(
            name: node.name,
            kind: content.typeKind,
            stereotype: CustomDiagram.Node.Content.type(content).stereotype,
            genericParameters: content.genericParameters,
            properties: content.properties.map { member in
                MemberDisplayItem(
                    id: member.id.uuidString,
                    text: Self.formatCustomMember(member, isMethod: false),
                    isStatic: member.isStatic,
                    isAbstract: member.isAbstract
                )
            },
            methods: content.methods.map { member in
                MemberDisplayItem(
                    id: member.id.uuidString,
                    text: Self.formatCustomMember(member, isMethod: true),
                    isStatic: member.isStatic,
                    isAbstract: member.isAbstract
                )
            },
            enumCases: content.enumCases.map { enumCase in
                EnumCaseDisplayItem(
                    id: enumCase.id.uuidString,
                    text: enumCase.name + (enumCase.associatedValues.isEmpty ? "" : "(\(enumCase.associatedValues))")
                )
            },
            isSelected: isSelected
        )
    }

    private static func formatCustomMember(_ member: CustomDiagram.Node.Member, isMethod: Bool) -> String {
        let symbol = member.accessLevel.umlSymbol
        if isMethod {
            return "\(symbol) \(member.name)(\(member.parameters))\(member.type.isEmpty ? "" : ": \(member.type)")"
        } else {
            return "\(symbol) \(member.name)\(member.type.isEmpty ? "" : ": \(member.type)")"
        }
    }
}
