import SwiftUI
import UMLCore

// MARK: - Display Data Types

/// A pre-formatted member line for display in a UML type box.
public struct MemberDisplayItem: Identifiable {
    public let id: String
    public let text: String
    public let isStatic: Bool
    public let isAbstract: Bool

    public init(id: String, text: String, isStatic: Bool, isAbstract: Bool) {
        self.id = id
        self.text = text
        self.isStatic = isStatic
        self.isAbstract = isAbstract
    }
}

/// A pre-formatted enum case line for display in a UML type box.
public struct EnumCaseDisplayItem: Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

// MARK: - UML Type Box View

/// Renders a code-type node as a three-compartment UML class box.
/// Used by both generated diagrams (from `GeneratedDiagramNode`) and freeform diagrams
/// (from `FreeformDiagram.Node` + `TypeNodeContent`).
public struct TypeNodeView: View {
    let name: String
    let kind: TypeKind
    let stereotype: String?
    let genericParameters: [String]
    let properties: [MemberDisplayItem]
    let methods: [MemberDisplayItem]
    let enumCases: [EnumCaseDisplayItem]
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    /// Primitive designated initializer. Both the generated-diagram and freeform-diagram
    /// convenience initializers (the latter lives in `UMLApp`) delegate here, so it must
    /// be `public` to be reachable from a cross-module extension.
    public init(
        name: String,
        kind: TypeKind,
        stereotype: String?,
        genericParameters: [String],
        properties: [MemberDisplayItem],
        methods: [MemberDisplayItem],
        enumCases: [EnumCaseDisplayItem],
        isSelected: Bool
    ) {
        self.name = name
        self.kind = kind
        self.stereotype = stereotype
        self.genericParameters = genericParameters
        self.properties = properties
        self.methods = methods
        self.enumCases = enumCases
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            kindDivider
            propertiesSection
            kindDivider
            methodsSection
            if !enumCases.isEmpty {
                kindDivider
                enumCasesSection
            }
        }
        .background(palette.bodyBackground(for: kind))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor : palette.border(for: kind), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            if let stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(palette.accent(for: kind))
            }
            Text(displayName)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.primaryInk)
                .if(isInterface) { $0.italic() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.headerBackground(for: kind))
    }

    private var displayName: String {
        var result = name
        if !genericParameters.isEmpty {
            result += "<" + genericParameters.joined(separator: ", ") + ">"
        }
        return result
    }

    private var isInterface: Bool {
        kind == .protocol || kind == .interface
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            if properties.isEmpty {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.clear)
            } else {
                ForEach(properties) { member in
                    memberRow(member)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Methods

    private var methodsSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            if methods.isEmpty {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.clear)
            } else {
                ForEach(methods) { member in
                    memberRow(member)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Enum Cases

    private var enumCasesSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(enumCases) { ec in
                Text(ec.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.secondaryInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Member Row

    private func memberRow(_ member: MemberDisplayItem) -> some View {
        Text(member.text)
            .font(.system(size: 11, design: .monospaced))
            .if(member.isStatic) { $0.underline() }
            .if(member.isAbstract) { $0.italic() }
            .foregroundColor(palette.secondaryInk)
            .lineLimit(1)
    }

    // MARK: - Divider

    private var kindDivider: some View {
        Rectangle()
            .fill(palette.border(for: kind).opacity(0.5))
            .frame(height: 1)
    }
}

// MARK: - UMLTypeBoxView Convenience Initializers

extension TypeNodeView {
    public init(node: GeneratedDiagramNode, isSelected: Bool) {
        self.init(
            name: node.name,
            kind: node.kind,
            stereotype: node.stereotype,
            genericParameters: node.genericParameters,
            properties: node.properties
                .removingDuplicates(by: \.id)
                .map { m in
                    MemberDisplayItem(id: m.id, text: m.displayText, isStatic: m.isStatic, isAbstract: m.isAbstract)
                },
            methods: node.methods
                .removingDuplicates(by: \.id)
                .map { m in
                    MemberDisplayItem(id: m.id, text: m.displayText, isStatic: m.isStatic, isAbstract: m.isAbstract)
                },
            enumCases: node.enumCases
                .removingDuplicates(by: \.id)
                .map { enumCase in
                    EnumCaseDisplayItem(id: enumCase.id, text: enumCase.displayText)
                },
            isSelected: isSelected
        )
    }
}
