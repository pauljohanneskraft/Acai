import SwiftUI
import AcaiCore
import AcaiRender

// MARK: - Freeform-diagram convenience initializer
//
// `TypeNodeView` lives in `AcaiRender` (shared with the CLI image renderer), but freeform
// diagrams are an app-only concept, so this initializer stays here and delegates to the
// shared view's primitive initializer.
extension TypeNodeView {
    init(node: FreeformDiagram.Node, content: FreeformDiagram.Node.TypeContent, isSelected: Bool) {
        self.init(
            name: node.name,
            kind: content.typeKind,
            stereotype: FreeformDiagram.Node.Content.type(content).stereotype,
            genericParameters: content.genericParameters,
            properties: content.properties.map(\.displayItem),
            methods: content.methods.map(\.displayItem),
            enumCases: content.enumCases.map { enumCase in
                EnumCaseDisplayItem(
                    id: enumCase.id.uuidString,
                    text: enumCase.name + (enumCase.associatedValues.isEmpty ? "" : "(\(enumCase.associatedValues))")
                )
            },
            isSelected: isSelected
        )
    }
}
