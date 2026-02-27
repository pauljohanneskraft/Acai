import SwiftUI
import UMLCore

// MARK: - Display Data Types

/// A pre-formatted member line for display in a UML type box.
struct MemberDisplayItem: Identifiable {
    let id: String
    let text: String
    let isStatic: Bool
    let isAbstract: Bool
}

/// A pre-formatted enum case line for display in a UML type box.
struct EnumCaseDisplayItem: Identifiable {
    let id: String
    let text: String
}

// MARK: - UML Type Box View

/// Renders a code-type node as a three-compartment UML class box.
/// Used by both generated diagrams (from `DiagramNode`) and custom diagrams
/// (from `CustomDiagramNode` + `TypeNodeContent`).
struct UMLTypeBoxView: View {
    let name: String
    let kind: TypeKind
    let stereotype: String?
    let genericParameters: [String]
    let properties: [MemberDisplayItem]
    let methods: [MemberDisplayItem]
    let enumCases: [EnumCaseDisplayItem]
    let isSelected: Bool

    var body: some View {
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
        .background(kindBodyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor : kindBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            if let stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(kindColor)
            }
            Text(displayName)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
                .conditionalModifier(isInterface) { $0.italic() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(kindHeaderBackground)
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
                    .foregroundColor(Color(white: 0.15))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Member Row

    private func memberRow(_ member: MemberDisplayItem) -> some View {
        Text(member.text)
            .font(.system(size: 11, design: .monospaced))
            .conditionalModifier(member.isStatic) { $0.underline() }
            .conditionalModifier(member.isAbstract) { $0.italic() }
            .foregroundColor(Color(white: 0.15))
            .lineLimit(1)
    }

    // MARK: - Divider

    private var kindDivider: some View {
        Rectangle()
            .fill(kindBorderColor.opacity(0.5))
            .frame(height: 1)
    }

    // MARK: - Kind-based solid colors

    private var kindColor: Color {
        switch kind {
        case .protocol, .interface:
            .blue
        case .struct, .record:
            .green
        case .enum:
            .orange
        case .class:
            .purple
        case .trait:
            .teal
        case .mixin:
            .indigo
        default:
            .gray
        }
    }

    private var kindHeaderBackground: Color {
        switch kind {
        case .protocol, .interface:
            Color(red: 0.93, green: 0.95, blue: 1.0)
        case .struct, .record:
            Color(red: 0.93, green: 0.98, blue: 0.93)
        case .enum:
            Color(red: 1.0, green: 0.96, blue: 0.92)
        case .class:
            Color(red: 0.96, green: 0.93, blue: 1.0)
        case .trait:
            Color(red: 0.92, green: 0.98, blue: 0.98)
        case .mixin:
            Color(red: 0.95, green: 0.93, blue: 1.0)
        default:
            Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }

    private var kindBodyBackground: Color {
        switch kind {
        case .protocol, .interface:
            Color(red: 0.97, green: 0.98, blue: 1.0)
        case .struct, .record:
            Color(red: 0.97, green: 0.99, blue: 0.97)
        case .enum:
            Color(red: 1.0, green: 0.99, blue: 0.97)
        case .class:
            Color(red: 0.99, green: 0.97, blue: 1.0)
        case .trait:
            Color(red: 0.97, green: 0.99, blue: 0.99)
        case .mixin:
            Color(red: 0.98, green: 0.97, blue: 1.0)
        default:
            Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }

    private var kindBorderColor: Color {
        switch kind {
        case .protocol, .interface:
            Color(red: 0.55, green: 0.62, blue: 0.85)
        case .struct, .record:
            Color(red: 0.50, green: 0.72, blue: 0.50)
        case .enum:
            Color(red: 0.82, green: 0.68, blue: 0.45)
        case .class:
            Color(red: 0.68, green: 0.52, blue: 0.82)
        case .trait:
            Color(red: 0.45, green: 0.72, blue: 0.72)
        case .mixin:
            Color(red: 0.58, green: 0.52, blue: 0.82)
        default:
            Color(red: 0.70, green: 0.70, blue: 0.70)
        }
    }
}

// MARK: - UMLTypeBoxView Convenience Initializers

extension UMLTypeBoxView {
    /// Create from a generated `DiagramNode`.
    init(node: DiagramNode, isSelected: Bool) {
        self.name = node.name
        self.kind = node.kind
        self.stereotype = node.stereotype
        self.genericParameters = node.genericParameters
        self.isSelected = isSelected

        // Deduplicate members from generated diagrams.
        var seenProps = Set<String>()
        self.properties = node.properties.compactMap { m in
            guard seenProps.insert(m.id).inserted else { return nil }
            return MemberDisplayItem(id: m.id, text: m.displayText, isStatic: m.isStatic, isAbstract: m.isAbstract)
        }
        var seenMethods = Set<String>()
        self.methods = node.methods.compactMap { m in
            guard seenMethods.insert(m.id).inserted else { return nil }
            return MemberDisplayItem(id: m.id, text: m.displayText, isStatic: m.isStatic, isAbstract: m.isAbstract)
        }
        var seenCases = Set<String>()
        self.enumCases = node.enumCases.compactMap { enumCase in
            guard seenCases.insert(enumCase.id).inserted else { return nil }
            return EnumCaseDisplayItem(id: enumCase.id, text: enumCase.displayText)
        }
    }

    /// Create from a custom diagram node with type content.
    init(node: CustomDiagramNode, content: TypeNodeContent, isSelected: Bool) {
        self.name = node.name
        self.kind = content.typeKind
        self.stereotype = NodeContent.type(content).stereotype
        self.genericParameters = content.genericParameters
        self.isSelected = isSelected

        self.properties = content.properties.map { member in
            MemberDisplayItem(
                id: member.id.uuidString,
                text: Self.formatCustomMember(member, isMethod: false),
                isStatic: member.isStatic,
                isAbstract: member.isAbstract
            )
        }
        self.methods = content.methods.map { member in
            MemberDisplayItem(
                id: member.id.uuidString,
                text: Self.formatCustomMember(member, isMethod: true),
                isStatic: member.isStatic,
                isAbstract: member.isAbstract
            )
        }
        self.enumCases = content.enumCases.map { enumCase in
            EnumCaseDisplayItem(
                id: enumCase.id.uuidString,
                text: enumCase.name + (enumCase.associatedValues.isEmpty ? "" : "(\(enumCase.associatedValues))")
            )
        }
    }

    private static func formatCustomMember(_ member: CustomMember, isMethod: Bool) -> String {
        let symbol = member.accessLevel.umlSymbol
        if isMethod {
            return "\(symbol) \(member.name)(\(member.parameters))\(member.type.isEmpty ? "" : ": \(member.type)")"
        } else {
            return "\(symbol) \(member.name)\(member.type.isEmpty ? "" : ": \(member.type)")"
        }
    }
}
