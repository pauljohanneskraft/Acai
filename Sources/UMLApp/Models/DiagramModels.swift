import Foundation
import UMLCore

// MARK: - Diagram Node

struct DiagramNode: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: TypeKind
    let stereotype: String?
    let properties: [DiagramMember]
    let methods: [DiagramMember]
    let enumCases: [DiagramEnumCase]
    let genericParameters: [String]

    init(from type: TypeDeclaration) {
        self.id = type.name
        self.name = type.name
        self.kind = type.kind
        self.stereotype = UMLMemberFormatting.stereotypeString(for: type.kind)
        self.genericParameters = type.genericParameters.map(\.name)

        let props = type.members.filter { $0.kind == .property || $0.kind == .subscript }
        let meths = type.members.filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }

        self.properties = props.map { DiagramMember(from: $0, isMethod: false) }
        self.methods = meths.map { DiagramMember(from: $0, isMethod: true) }
        self.enumCases = type.enumCases.map { DiagramEnumCase(from: $0) }
    }
}

// MARK: - Diagram Member

struct DiagramMember: Identifiable, Sendable {
    let id: String
    let accessSymbol: String
    let name: String
    let displayText: String
    let isStatic: Bool
    let isAbstract: Bool

    init(from member: Member, isMethod: Bool) {
        self.id = "\(member.name)_\(member.kind.rawValue)_\(member.type?.name ?? "")"
        self.accessSymbol = member.accessLevel?.umlSymbol ?? "~"
        self.name = member.name
        self.isStatic = member.modifiers.contains(.static) || member.modifiers.contains(.class)
        self.isAbstract = member.modifiers.contains(.abstract)

        if isMethod {
            self.displayText = UMLMemberFormatting.formatMethod(member)
        } else {
            self.displayText = UMLMemberFormatting.formatProperty(member)
        }
    }
}

// MARK: - Diagram Enum Case

struct DiagramEnumCase: Identifiable, Sendable {
    let id: String
    let displayText: String

    init(from enumCase: EnumCase) {
        self.id = enumCase.name
        self.displayText = UMLMemberFormatting.formatEnumCase(enumCase)
    }
}

// MARK: - Diagram Edge

struct DiagramEdge: Identifiable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let kind: Relationship.Kind

    init(from rel: Relationship) {
        self.id = "\(rel.source)-\(rel.kind.rawValue)-\(rel.target)"
        self.sourceID = rel.source
        self.targetID = rel.target
        self.kind = rel.kind
    }
}
