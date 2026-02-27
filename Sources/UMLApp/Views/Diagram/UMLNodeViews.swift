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
        case .protocol, .interface: .blue
        case .struct, .record:      .green
        case .enum:                 .orange
        case .class:                .purple
        case .trait:                .teal
        case .mixin:                .indigo
        default:                    .gray
        }
    }

    private var kindHeaderBackground: Color {
        switch kind {
        case .protocol, .interface: Color(red: 0.93, green: 0.95, blue: 1.0)
        case .struct, .record:      Color(red: 0.93, green: 0.98, blue: 0.93)
        case .enum:                 Color(red: 1.0, green: 0.96, blue: 0.92)
        case .class:                Color(red: 0.96, green: 0.93, blue: 1.0)
        case .trait:                Color(red: 0.92, green: 0.98, blue: 0.98)
        case .mixin:                Color(red: 0.95, green: 0.93, blue: 1.0)
        default:                    Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }

    private var kindBodyBackground: Color {
        switch kind {
        case .protocol, .interface: Color(red: 0.97, green: 0.98, blue: 1.0)
        case .struct, .record:      Color(red: 0.97, green: 0.99, blue: 0.97)
        case .enum:                 Color(red: 1.0, green: 0.99, blue: 0.97)
        case .class:                Color(red: 0.99, green: 0.97, blue: 1.0)
        case .trait:                Color(red: 0.97, green: 0.99, blue: 0.99)
        case .mixin:                Color(red: 0.98, green: 0.97, blue: 1.0)
        default:                    Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }

    private var kindBorderColor: Color {
        switch kind {
        case .protocol, .interface: Color(red: 0.55, green: 0.62, blue: 0.85)
        case .struct, .record:      Color(red: 0.50, green: 0.72, blue: 0.50)
        case .enum:                 Color(red: 0.82, green: 0.68, blue: 0.45)
        case .class:                Color(red: 0.68, green: 0.52, blue: 0.82)
        case .trait:                Color(red: 0.45, green: 0.72, blue: 0.72)
        case .mixin:                Color(red: 0.58, green: 0.52, blue: 0.82)
        default:                    Color(red: 0.70, green: 0.70, blue: 0.70)
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

// MARK: - Actor Node View

/// Renders a UML actor as a labelled stick-figure icon.
struct UMLActorNodeView: View {
    let name: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 0.95, green: 0.99, blue: 0.99)
    private let borderColor = Color(red: 0.45, green: 0.72, blue: 0.72)
    private let iconColor = Color(red: 0.30, green: 0.60, blue: 0.60)

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "person")
                .font(.system(size: 28))
                .foregroundColor(iconColor)
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Use Case Node View

/// Renders a UML use case as a labelled ellipse.
struct UMLUseCaseNodeView: View {
    let name: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 0.96, green: 0.95, blue: 1.0)
    private let borderColor = Color(red: 0.58, green: 0.52, blue: 0.82)

    var body: some View {
        Text(name)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(Color(white: 0.1))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .clipShape(Ellipse())
            .overlay(
                Ellipse()
                    .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Container Node View (package, boundary, subsystem)

/// A resizable UML container node. Used for package (tabbed folder), boundary (dashed
/// rectangle), and subsystem (component-style container).
struct UMLContainerNodeView: View {
    let name: String
    let stereotype: String
    let style: Style
    let isSelected: Bool
    let size: CGSize?

    enum Style {
        case package, boundary, subsystem

        var fillColor: Color {
            switch self {
            case .package:   Color(red: 0.96, green: 0.93, blue: 0.88)
            case .boundary:  Color(red: 1.0, green: 0.97, blue: 0.90)
            case .subsystem: Color(red: 0.90, green: 0.96, blue: 0.98)
            }
        }

        var headerColor: Color {
            switch self {
            case .package:   Color(red: 0.91, green: 0.86, blue: 0.78)
            case .boundary:  Color(red: 0.96, green: 0.92, blue: 0.82)
            case .subsystem: Color(red: 0.82, green: 0.92, blue: 0.96)
            }
        }

        var borderColor: Color {
            switch self {
            case .package:   Color(red: 0.68, green: 0.58, blue: 0.42)
            case .boundary:  Color(red: 0.78, green: 0.65, blue: 0.35)
            case .subsystem: Color(red: 0.40, green: 0.65, blue: 0.75)
            }
        }

        var isDashed: Bool {
            self == .boundary
        }
    }

    var body: some View {
        let width = size?.width ?? 200
        let height = size?.height ?? 150
        let border = isSelected ? Color.accentColor : style.borderColor
        let lineWidth: CGFloat = isSelected ? 2 : 1

        VStack(alignment: .leading, spacing: 0) {
            // Header with stereotype + name
            VStack(spacing: 1) {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(style.borderColor)
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(style.headerColor)

            // Divider
            Rectangle()
                .fill(border)
                .frame(height: lineWidth)

            // Open body area
            Spacer()
        }
        .frame(width: width, height: height)
        .background(style.fillColor)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(border, style: style.isDashed
                    ? StrokeStyle(lineWidth: lineWidth, dash: [6, 4])
                    : StrokeStyle(lineWidth: lineWidth))
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Database Node View

/// Renders a UML database as a cylinder shape.
struct UMLDatabaseNodeView: View {
    let name: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 1.0, green: 0.96, blue: 0.97)
    private let borderColor = Color(red: 0.82, green: 0.52, blue: 0.58)
    private let iconColor = Color(red: 0.72, green: 0.40, blue: 0.48)

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cylinder")
                .font(.system(size: 26))
                .foregroundColor(iconColor)
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Note Node View

/// Renders a UML note as a dog-eared rectangle.
struct UMLNoteNodeView: View {
    let name: String
    let text: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 1.0, green: 0.99, blue: 0.94)
    private let borderColor = Color(red: 0.82, green: 0.75, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
            Text(text.isEmpty ? "(empty note)" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(text.isEmpty ? Color(white: 0.5) : Color(white: 0.15))
                .lineLimit(8)
        }
        .padding(10)
        .frame(minWidth: 100, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Stereotyped Box Node View

/// A generic labelled box with a stereotype header. Used for component,
/// deployment node, artifact, entity, etc.
struct UMLStereotypedBoxNodeView: View {
    let name: String
    let stereotype: String?
    let systemImage: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 0.95, green: 0.98, blue: 0.99)
    private let borderColor = Color(red: 0.40, green: 0.65, blue: 0.75)
    private let iconColor = Color(red: 0.30, green: 0.55, blue: 0.65)

    var body: some View {
        VStack(spacing: 4) {
            if let stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(borderColor)
            }
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func conditionalModifier<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension Sequence {
    func removingDuplicates<P: Hashable>(by property: (Element) -> P) -> [Element] {
        var existing = Set<P>()
        return filter { existing.insert(property($0)).inserted }
    }
}
