/// The module and file scopes a type id can be qualified by.
public struct TypeIDScope: Sendable {
    public let filePath: String
    public let module: String

    public init(filePath: String, module: String) {
        self.filePath = filePath
        self.module = module
    }

    public func moduleScoped(_ id: String) -> String {
        "\(module).\(id)"
    }

    /// `Sources/AcaiCLI/Main.swift:ThemeOption`; the colon keeps the path out of the dotted name.
    public func fileScoped(_ id: String) -> String {
        "\(filePath):\(id)"
    }

    public func unqualified(_ id: String) -> String {
        if id.hasPrefix(filePath + ":") { return String(id.dropFirst(filePath.count + 1)) }
        if id.hasPrefix(module + ".") { return String(id.dropFirst(module.count + 1)) }
        return id
    }
}

extension TypeDeclaration {
    /// An unscoped type falls back to the module ``ModuleResolver/standard`` derives from its path.
    public var idScope: TypeIDScope {
        let filePath = location?.filePath ?? ""
        return TypeIDScope(
            filePath: filePath, module: module ?? ModuleResolver.standard.productName(forFilePath: filePath))
    }

    /// The id as its parser wrote it, before project analysis scoped it to a module or file.
    public var unqualifiedID: String {
        module == nil ? id : idScope.unqualified(id)
    }

    /// A top-level `private`/`fileprivate` type is unique per file, not per module.
    var isFileScoped: Bool {
        accessLevel == .private || accessLevel == .filePrivate
    }

    fileprivate func stampingModule(from modules: ModuleMap) -> TypeDeclaration {
        var copy = self
        copy.module = modules.module(forFilePath: location?.filePath ?? "")
        copy.nestedTypes = nestedTypes.map { $0.stampingModule(from: modules) }
        return copy
    }
}

extension CodeArtifact {
    /// Prefixes each type id with its file's module in `modules` (`AcaiCLI.ThemeOption`), or its file if file-private.
    public func scopingTypeIDs(modules: ModuleMap) -> CodeArtifact {
        var stamped = self
        stamped.types = types.map { $0.stampingModule(from: modules) }
        return stamped.renamingTypeIDs { type in
            type.isFileScoped ? type.idScope.fileScoped(type.id) : type.idScope.moduleScoped(type.id)
        }
    }

    /// Re-scopes each type declaring an id in `collidingIDs` from its module to its file.
    public func qualifyingTypeIDsByFile(collidingIDs: Set<String>) -> CodeArtifact {
        renamingTypeIDs { type in
            guard type.declaresAnyID(in: collidingIDs) else { return nil }
            return type.idScope.fileScoped(type.unqualifiedID)
        }
    }

    /// Asks `newID` per top-level type and per type nested in an extension; nested types and edges follow.
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
