import Foundation
import UMLCore

// MARK: - Diagram Node

public struct GeneratedDiagramNode: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: TypeKind
    public let stereotype: String?
    public let properties: [DiagramMember]
    public let methods: [DiagramMember]
    public let enumCases: [DiagramEnumCase]
    public let genericParameters: [String]
    /// The full relative directory path of this type's source file (e.g.
    /// `Sources/UMLCore/ClassDiagram`), used for hierarchical directory grouping.
    public let directoryPath: String?
    /// The compiled product (build target / module) this type belongs to,
    /// derived from its source-file path. Used for product grouping and package boxes.
    public let productGroup: String?

    public init(from type: TypeDeclaration, configuration: DiagramConfiguration? = nil) {
        self.id = type.id
        self.name = type.name
        self.kind = type.kind
        self.stereotype = UMLMemberFormatting.stereotypeString(for: type.kind)
        self.genericParameters = type.genericParameters.map(\.name)

        let config = configuration ?? .init()
        let accessFilter = config.minimumAccessLevel

        let props = type.members.filter { $0.kind == .property || $0.kind == .subscript }
        let meths = type.members.filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }

        if config.showProperties {
            self.properties = props
                .filter { Self.passesAccessFilter($0.accessLevel, minimum: accessFilter) }
                .map { DiagramMember(from: $0, isMethod: false) }
        } else {
            self.properties = []
        }

        if config.showMethods {
            self.methods = meths
                .filter { Self.passesAccessFilter($0.accessLevel, minimum: accessFilter) }
                .map { DiagramMember(from: $0, isMethod: true) }
        } else {
            self.methods = []
        }

        if config.showEnumCases {
            self.enumCases = type.enumCases.map { DiagramEnumCase(from: $0) }
        } else {
            self.enumCases = []
        }

        // Extract the full directory path (all components except the file name) for
        // hierarchical grouping, plus the compiled product for product grouping.
        if let filePath = type.location?.filePath {
            let dirComponents = filePath.split(separator: "/").dropLast().map(String.init)
            self.directoryPath = dirComponents.isEmpty ? nil : dirComponents.joined(separator: "/")
            self.productGroup = BuildProduct.productName(forFilePath: filePath)
        } else {
            self.directoryPath = nil
            self.productGroup = nil
        }
    }

    /// Returns true if the given access level is at or above the minimum. Used both for
    /// member visibility and for hiding whole types below the minimum access level.
    public static func passesAccessFilter(_ memberAccess: AccessLevel?, minimum: AccessLevel?) -> Bool {
        guard let minimum else { return true }
        let order = accessOrder(memberAccess ?? .internal)
        let minOrder = accessOrder(minimum)
        return order >= minOrder
    }

    /// Numeric visibility ordering: higher = more visible.
    private static func accessOrder(_ level: AccessLevel) -> Int {
        switch level {
        case .open:
            return 6
        case .public:
            return 5
        case .packagePrivate:
            return 4
        case .internal:
            return 3
        case .protected:
            return 2
        case .filePrivate:
            return 1
        case .private:
            return 0
        }
    }
}

// MARK: - Diagram Member

public struct DiagramMember: Identifiable, Sendable {
    public let id: String
    public let accessSymbol: String
    public let name: String
    public let displayText: String
    public let isStatic: Bool
    public let isAbstract: Bool

    public init(from member: Member, isMethod: Bool) {
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

public struct DiagramEnumCase: Identifiable, Sendable {
    public let id: String
    public let displayText: String

    public init(from enumCase: EnumCase) {
        self.id = enumCase.name
        self.displayText = UMLMemberFormatting.formatEnumCase(enumCase)
    }
}

// MARK: - Diagram Edge

public struct GeneratedDiagramEdge: Identifiable, Sendable {
    public let id: String
    public let sourceID: String
    public let targetID: String
    public let kind: Relationship.Kind

    public init(from rel: Relationship) {
        self.id = "\(rel.source)-\(rel.kind.rawValue)-\(rel.target)"
        self.sourceID = rel.source
        self.targetID = rel.target
        self.kind = rel.kind
    }
}
