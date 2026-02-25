import SwiftUI
import UMLCore

/// Renders a single UML class box with proper compartments:
/// header (stereotype + name), properties, methods, and optionally enum cases.
struct UMLClassBoxView: View {
    let node: DiagramNode
    let isSelected: Bool

    private var isInterface: Bool {
        node.kind == .protocol || node.kind == .interface
    }

    private var isDashed: Bool {
        node.kind == .extension
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            divider
            propertiesSection
            divider
            methodsSection
            if !node.enumCases.isEmpty {
                divider
                enumCasesSection
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isSelected ? Color.accentColor : Color(white: 0.25),
                    lineWidth: isSelected ? 2 : 1
                )
                .if(isDashed) { view in
                    view.opacity(1)
                }
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            if let stereotype = node.stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            Text(displayName)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
                .if(isInterface) { $0.italic() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
    }

    private var displayName: String {
        var name = node.name
        if !node.genericParameters.isEmpty {
            name += "<" + node.genericParameters.joined(separator: ", ") + ">"
        }
        return name
    }

    private var headerBackground: some View {
        let color: Color = switch node.kind {
        case .protocol, .interface:
            Color.blue.opacity(0.06)
        case .struct, .record:
            Color.green.opacity(0.06)
        case .enum:
            Color.orange.opacity(0.06)
        case .class:
            Color.purple.opacity(0.06)
        default:
            Color.gray.opacity(0.04)
        }
        return color
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            if node.properties.isEmpty {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.clear)
            } else {
                ForEach(node.properties) { member in
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
            if node.methods.isEmpty {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.clear)
            } else {
                ForEach(node.methods) { member in
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
            ForEach(node.enumCases) { enumCase in
                Text(enumCase.displayText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.2))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Member Row

    private func memberRow(_ member: DiagramMember) -> some View {
        Text(member.displayText)
            .font(.system(size: 11, design: .monospaced))
            .if(member.isStatic) { $0.underline() }
            .if(member.isAbstract) { $0.italic() }
            .foregroundColor(Color(white: 0.2))
            .lineLimit(1)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.25))
            .frame(height: 1)
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
