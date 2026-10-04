/// The scopes a type id can be qualified by, derived from the relative path of the file declaring
/// the type: its build module (via ``ModuleResolver``) and, for a name its module still declares in
/// more than one file, the file itself.
public struct TypeIDScope: Sendable {
    public let filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }

    public var module: String {
        ModuleResolver.standard.productName(forFilePath: filePath)
    }

    public func moduleScoped(_ id: String) -> String {
        "\(module).\(id)"
    }

    /// `Sources/AcaiCLI/Main.swift:ThemeOption` — the colon keeps the path from reading as part of a
    /// dotted name, so ``unqualified(_:)`` can strip it exactly.
    public func fileScoped(_ id: String) -> String {
        "\(filePath):\(id)"
    }

    /// `id` with the scope project analysis prefixed it with removed — the id as the parser wrote it.
    public func unqualified(_ id: String) -> String {
        if id.hasPrefix(filePath + ":") { return String(id.dropFirst(filePath.count + 1)) }
        if id.hasPrefix(module + ".") { return String(id.dropFirst(module.count + 1)) }
        return id
    }
}

extension TypeDeclaration {
    public var idScope: TypeIDScope {
        TypeIDScope(filePath: location?.filePath ?? "")
    }

    /// The id as its parser wrote it, before project analysis scoped it to a module or file.
    public var unqualifiedID: String {
        idScope.unqualified(id)
    }
}

extension CodeArtifact {
    /// Prefixes every type id with the build module of the file declaring it, so same-named types in
    /// two modules (`AcaiCLI.ThemeOption`, `AcaiMCP.ThemeOption`) stay distinct. Applied once per
    /// parsed file, before files are merged.
    public func qualifyingTypeIDsByModule() -> CodeArtifact {
        renamingTypeIDs { $0.idScope.moduleScoped($0.id) }
    }

    /// Re-scopes each type whose id (or a nested type's id) is in `collidingIDs` from its module to
    /// its file — for a name its module declares in more than one file.
    public func qualifyingTypeIDsByFile(collidingIDs: Set<String>) -> CodeArtifact {
        renamingTypeIDs { type in
            guard type.declaresAnyID(in: collidingIDs) else { return nil }
            return type.idScope.fileScoped(type.unqualifiedID)
        }
    }

    /// `newID` is asked for each top-level declaration (and each type nested in an extension, which
    /// keeps its own unscoped id); nested types follow their parent. Relationship endpoints naming a
    /// renamed id follow too.
    private func renamingTypeIDs(_ newID: (TypeDeclaration) -> String?) -> CodeArtifact {
        var renames: [String: String] = [:]
        var copy = self
        copy.types = types.map { $0.renamingID(newID, renames: &renames) }
        guard !renames.isEmpty else { return copy }
        copy.relationships = relationships.map { relationship in
            var renamed = relationship
            renamed.source = renames[relationship.source] ?? relationship.source
            renamed.target = renames[relationship.target] ?? relationship.target
            return renamed
        }
        return copy
    }
}

extension TypeDeclaration {
    fileprivate func declaresAnyID(in ids: Set<String>) -> Bool {
        ids.contains(id) || nestedTypes.contains { $0.declaresAnyID(in: ids) }
    }

    fileprivate func renamingID(
        _ newID: (TypeDeclaration) -> String?, renames: inout [String: String]
    ) -> TypeDeclaration {
        guard kind != .extension else {
            var copy = self
            copy.nestedTypes = nestedTypes.map { $0.renamingID(newID, renames: &renames) }
            return copy
        }
        guard let id = newID(self) else { return self }
        return identified(as: id, renames: &renames)
    }

    private func identified(as newID: String, renames: inout [String: String]) -> TypeDeclaration {
        renames[id] = newID
        var copy = self
        copy.id = newID
        copy.qualifiedName = newID
        copy.nestedTypes = nestedTypes.map { nested in
            let suffix = nested.id.hasPrefix(id + ".") ? String(nested.id.dropFirst(id.count)) : ".\(nested.name)"
            return nested.identified(as: newID + suffix, renames: &renames)
        }
        return copy
    }
}

/// The type ids that two or more files declare, across every parsed file of a project.
public struct CollidingTypeIDs: Sendable {
    public let ids: Set<String>

    public init(files: [CodeArtifact]) {
        var filesByID: [String: Set<String>] = [:]
        for file in files {
            for type in file.flattened() where type.kind != .extension {
                filesByID[type.id, default: []].insert(type.location?.filePath ?? "")
            }
        }
        ids = Set(filesByID.filter { $0.value.count > 1 }.keys)
    }

    public func disambiguating(_ file: CodeArtifact) -> CodeArtifact {
        guard !ids.isEmpty else { return file }
        return file.qualifyingTypeIDsByFile(collidingIDs: ids)
    }
}
