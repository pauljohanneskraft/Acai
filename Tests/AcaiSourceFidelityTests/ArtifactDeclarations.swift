import AcaiCore

/// A type reference as the artifact carries it, with the role that names it in a failure.
struct SpelledType: Sendable {
    let role: String
    let reference: TypeReference
    /// Whether this is a constructor parameter that could be taking its type from a field of the
    /// same name, rather than writing one.
    var mayTakeTypeFromField = false
}

/// One declaration the checks hold to its own source: the name that has to appear inside its span,
/// the location it claims, and every type it spells.
struct LocatedDeclaration: Sendable {
    let label: String
    let name: String
    let location: SourceLocation?
    var spelledTypes: [SpelledType] = []
}

/// Flattens an artifact into the declarations the checks run on, nested types and extension bodies
/// included, so a declaration cannot escape a check by sitting one level down.
struct ArtifactDeclarations {
    let artifact: CodeArtifact

    var all: [LocatedDeclaration] {
        artifact.types.flatMap { declarations(of: $0) }
            + artifact.freestandingFunctions.map { declaration(of: $0, in: nil) }
            + artifact.globalVariables.map { declaration(of: $0, in: nil) }
    }

    /// Every declared type including nested ones, in declaration order.
    var allTypes: [TypeDeclaration] {
        artifact.types.flatMap { flatten($0) }
    }

    private func flatten(_ type: TypeDeclaration) -> [TypeDeclaration] {
        [type] + type.nestedTypes.flatMap { flatten($0) }
    }

    private func declarations(of type: TypeDeclaration) -> [LocatedDeclaration] {
        [LocatedDeclaration(label: "type \(type.id)", name: type.name, location: type.location)]
            + type.members.map { declaration(of: $0, in: type) }
            + type.enumCases.map { enumCase in
                LocatedDeclaration(
                    label: "case \(type.name).\(enumCase.name)",
                    name: enumCase.name,
                    location: enumCase.location
                )
            }
            + type.nestedTypes.flatMap { declarations(of: $0) }
    }

    private func declaration(of member: Member, in type: TypeDeclaration?) -> LocatedDeclaration {
        let owner = type.map { "\($0.name)." } ?? ""
        return LocatedDeclaration(
            label: "member \(owner)\(member.name)",
            name: member.name,
            location: member.location,
            spelledTypes: spelledTypes(of: member, in: type)
        )
    }

    private func spelledTypes(of member: Member, in type: TypeDeclaration?) -> [SpelledType] {
        let own = member.type.map { [SpelledType(role: "type", reference: $0)] } ?? []
        return own + member.parameters.compactMap { parameter in
            parameter.type.map {
                SpelledType(
                    role: "parameter '\(parameter.internalName)'",
                    reference: $0,
                    mayTakeTypeFromField: member.kind == .initializer && initializes(parameter, of: type)
                )
            }
        }
    }

    /// Whether the owning type declares a member this parameter could be initializing directly.
    private func initializes(_ parameter: Parameter, of type: TypeDeclaration?) -> Bool {
        guard let type else { return false }
        return type.members.contains { $0.name == parameter.internalName && $0.type == parameter.type }
    }
}
