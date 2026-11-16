import Foundation

/// Injected per ``AnalysisService`` rather than static, so suites running in one process don't mix totals.
public final class TypeFlattenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var passes = 0

    public init() {}

    public var count: Int {
        lock.withLock { passes }
    }

    func recordPass() {
        lock.withLock { passes += 1 }
    }
}

extension CodeArtifact {
    func resolvingExtensions(counting counter: TypeFlattenCounter?) -> CodeArtifact {
        let extensions = types.filter { $0.kind == .extension }
        var resolved = ExtensionTargetIndex(
            types: types.filter { $0.kind != .extension }, counting: counter)
        // Drop any standalone extension edges; conformances are re-derived below so
        // their source is the real target id (never a dangling `extension.*` node).
        var resolvedRelationships = relationships.filter { $0.kind != .extension }

        for ext in extensions {
            guard let targetName = ext.extensionOf,
                  let targetId = resolved.merge(ext, targetName: targetName)
            else {
                // Extension of an external type (e.g. `extension Array`): dropped entirely.
                continue
            }
            for inherited in ext.inheritedTypes {
                // Attributed to the extension's module (not the extended type's) for coupling/cycles,
                // since the conformance is declared by the extension.
                resolvedRelationships.append(
                    Relationship(
                        kind: .conformance, source: targetId, target: inherited.name,
                        origin: ext.location?.filePath)
                )
            }
        }

        return CodeArtifact(
            metadata: metadata,
            types: resolved.types,
            relationships: resolvedRelationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }
}

extension String {
    /// `Foo<T>` → `Foo`, so an extension of a generic type matches the declaration's own name.
    var withoutGenericArguments: String {
        guard let start = firstIndex(of: "<") else { return self }
        return String(self[..<start]).trimmingCharacters(in: .whitespaces)
    }
}

extension TypeDeclaration {
    /// Conformances merge too, so protocol-witness dead-code exemption still sees them.
    fileprivate mutating func absorb(_ ext: TypeDeclaration) {
        members.append(contentsOf: ext.members)
        nestedTypes.append(contentsOf: ext.nestedTypes)
        let existingNames = Set(inheritedTypes.map(\.name))
        inheritedTypes.append(contentsOf: ext.inheritedTypes.filter { !existingNames.contains($0.name) })
    }
}

extension Array where Element == TypeDeclaration {
    /// Every type including nested ones, pre-order, each copy's `nestedTypes` cleared.
    func flattenedTree(counting counter: TypeFlattenCounter?) -> [TypeDeclaration] {
        counter?.recordPass()
        var result: [TypeDeclaration] = []
        appendFlattened(into: &result)
        return result
    }

    private func appendFlattened(into result: inout [TypeDeclaration]) {
        for type in self {
            var copy = type
            copy.nestedTypes = []
            result.append(copy)
            type.nestedTypes.appendFlattened(into: &result)
        }
    }

    fileprivate func type(at path: ArraySlice<Int>) -> Element? {
        guard let index = path.first, indices.contains(index) else { return nil }
        return path.count == 1 ? self[index] : self[index].nestedTypes.type(at: path.dropFirst())
    }

    fileprivate mutating func absorb(_ ext: Element, at path: ArraySlice<Int>) {
        guard let index = path.first, indices.contains(index) else { return }
        if path.count == 1 {
            self[index].absorb(ext)
        } else {
            self[index].nestedTypes.absorb(ext, at: path.dropFirst())
        }
    }
}

/// A type tree indexed once for extension lookup; merged nested types are registered as they arrive.
struct ExtensionTargetIndex {
    private struct Entry {
        let id: String
        let module: String
        let path: [Int]
    }

    private(set) var types: [TypeDeclaration]
    private var entries: [Entry] = []
    /// The earliest-registered type per qualified name or id.
    private var entryByExactName: [String: Int] = [:]
    private var entriesBySimpleName: [String: [Int]] = [:]
    private var entriesByUnqualifiedID: [String: [Int]] = [:]

    init(types: [TypeDeclaration], counting counter: TypeFlattenCounter?) {
        self.types = types
        counter?.recordPass()
        for (offset, type) in types.enumerated() {
            register(type, at: [offset])
        }
    }

    private mutating func register(_ type: TypeDeclaration, at path: [Int]) {
        let index = entries.count
        entries.append(Entry(id: type.id, module: type.idScope.module, path: path))
        if entryByExactName[type.qualifiedName] == nil { entryByExactName[type.qualifiedName] = index }
        if entryByExactName[type.id] == nil { entryByExactName[type.id] = index }
        entriesBySimpleName[type.name, default: []].append(index)
        entriesByUnqualifiedID[type.unqualifiedID, default: []].append(index)
        for (offset, nested) in type.nestedTypes.enumerated() {
            register(nested, at: path + [offset])
        }
    }

    /// The target's id, or `nil` when the target is external and the extension is dropped.
    mutating func merge(_ ext: TypeDeclaration, targetName: String) -> String? {
        guard let target = targetEntry(for: ext, name: targetName.withoutGenericArguments) else { return nil }
        let path = entries[target].path
        let alreadyNested = types.type(at: path[...])?.nestedTypes.count ?? 0
        types.absorb(ext, at: path[...])
        for (offset, nested) in ext.nestedTypes.enumerated() {
            register(nested, at: path + [alreadyNested + offset])
        }
        return entries[target].id
    }

    /// An exact id, else a sole same-module match, else a sole unqualified-id match; never a foreign simple name.
    private func targetEntry(for ext: TypeDeclaration, name: String) -> Int? {
        if let exact = entryByExactName[name] { return exact }
        let unqualifiedMatches = entriesByUnqualifiedID[name] ?? []
        var candidates = Set(entriesBySimpleName[name] ?? [])
        candidates.formUnion(unqualifiedMatches)
        let extModule = ext.idScope.module
        let sameModuleMatches = candidates.filter { entries[$0].module == extModule }
        if sameModuleMatches.count == 1 { return sameModuleMatches.first }
        guard sameModuleMatches.isEmpty, unqualifiedMatches.count == 1 else { return nil }
        return unqualifiedMatches[0]
    }
}
