import SwiftUI
import AcaiCore
import AcaiDiff

// MARK: - Display Data Types

public struct MemberDisplayItem: Identifiable {
    public let id: String
    public let text: String
    public let isStatic: Bool
    public let isAbstract: Bool
    public let accessLevel: AccessLevel

    public init(id: String, text: String, isStatic: Bool, isAbstract: Bool, accessLevel: AccessLevel) {
        self.id = id
        self.text = text
        self.isStatic = isStatic
        self.isAbstract = isAbstract
        self.accessLevel = accessLevel
    }
}

public struct EnumCaseDisplayItem: Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

// MARK: - UML Type Box View

public struct TypeNodeView: View {
    let name: String
    let kind: TypeKind
    let stereotype: String?
    let genericParameters: [String]
    let properties: [MemberDisplayItem]
    let methods: [MemberDisplayItem]
    let enumCases: [EnumCaseDisplayItem]
    let isSelected: Bool
    /// Optional delta border tint (added/removed/changed); colours the node's outline rather than
    /// its fill so the body text and theme stay readable. `nil` uses the themed border.
    let borderOverride: Color?
    /// Non-color complement to `borderOverride`; `nil` draws no badge.
    let badge: DeltaStatus?

    @Environment(\.diagramPalette) private var palette

    /// Primitive designated initializer. Both the generated-diagram and freeform-diagram
    /// convenience initializers (the latter lives in `AcaiApp`) delegate here, so it must
    /// be `public` to be reachable from a cross-module extension.
    public init(
        name: String,
        kind: TypeKind,
        stereotype: String?,
        genericParameters: [String],
        properties: [MemberDisplayItem],
        methods: [MemberDisplayItem],
        enumCases: [EnumCaseDisplayItem],
        isSelected: Bool,
        borderOverride: Color? = nil,
        badge: DeltaStatus? = nil
    ) {
        self.name = name
        self.kind = kind
        self.stereotype = stereotype
        self.genericParameters = genericParameters
        self.properties = properties
        self.methods = methods
        self.enumCases = enumCases
        self.isSelected = isSelected
        self.borderOverride = borderOverride
        self.badge = badge
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
                .stroke(
                    borderOverride ?? (isSelected ? Color.accentColor : palette.border(for: kind)),
                    lineWidth: borderOverride != nil ? 3 : (isSelected ? 2 : 1))
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .overlay(alignment: .topTrailing) {
            if let badge, badge.badgeGlyph != nil {
                DeltaBadgeView(status: badge)
                    .offset(x: 7, y: -7)
            }
        }
        // Keyed by name, not a stable id — `TypeNodeView` has no id of its own. Good enough for a
        // UI-test hook; a name collision within one diagram is a known edge case.
        .accessibilityIdentifier("diagram.typeNode.\(name)")
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
        MemberRowView(item: member, compact: true)
    }

    // MARK: - Divider

    private var kindDivider: some View {
        Rectangle()
            .fill(palette.border(for: kind).opacity(0.5))
            .frame(height: 1)
    }
}

// MARK: - TypeNodeView Convenience Initializers

extension TypeNodeView {
    public init(
        node: GeneratedDiagramNode, isSelected: Bool, borderOverride: Color? = nil, badge: DeltaStatus? = nil
    ) {
        self.init(
            name: node.name,
            kind: node.kind,
            stereotype: node.stereotype,
            genericParameters: node.genericParameters,
            properties: node.properties.removingDuplicates(by: \.id).map(\.displayItem),
            methods: node.methods.removingDuplicates(by: \.id).map(\.displayItem),
            enumCases: node.enumCases
                .removingDuplicates(by: \.id)
                .map { enumCase in
                    EnumCaseDisplayItem(id: enumCase.id, text: enumCase.displayText)
                },
            isSelected: isSelected,
            borderOverride: borderOverride,
            badge: badge
        )
    }
}

// MARK: - Delta Badge

private struct DeltaBadgeView: View {
    let status: DeltaStatus

    var body: some View {
        Text(status.badgeGlyph ?? "")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.badgeAccessibilityLabel ?? "")
    }

    private var fill: Color {
        status.deltaHex.map { Color(hex: $0) } ?? Color.secondary
    }
}
