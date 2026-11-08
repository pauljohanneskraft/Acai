import Foundation

/// Counts the type-tree flattening passes a pipeline runs, so a test can hold the count against an
/// input whose size it varies.
///
/// Injected per call and `nil` in production. Deliberately not a static: `swift test --parallel`
/// runs suites in one process, and a shared counter would mix their totals.
public final class TypeFlattenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var passes = 0

    public init() {}

    /// Flattening passes recorded — one per call that walks a tree, not one per recursive step.
    public var count: Int {
        lock.withLock { passes }
    }

    func recordPass() {
        lock.withLock { passes += 1 }
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
    /// Takes on an extension's members, nested types and new conformances.
    ///
    /// Conformances must merge too — dropping them would hide protocol conformance from anything
    /// reading `inheritedTypes` (e.g. protocol-witness dead-code exemption).
    fileprivate mutating func absorb(_ ext: TypeDeclaration) {
        members.append(contentsOf: ext.members)
        nestedTypes.append(contentsOf: ext.nestedTypes)
        let existingNames = Set(inheritedTypes.map(\.name))
        inheritedTypes.append(contentsOf: ext.inheritedTypes.filter { !existingNames.contains($0.name) })
    }
}

extension Array where Element == TypeDeclaration {
    /// Every type including nested ones, pre-order, each copy's `nestedTypes` cleared. Ids are
    /// already fully qualified, so they stay unique.
    func flattenedTree(counting counter: TypeFlattenCounter? = nil) -> [TypeDeclaration] {
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

/// A project's type tree plus the lookups extension resolution needs over it, built in one pass and
/// kept current as extensions merge.
///
/// Resolving an extension used to flatten every type again — a full recursive copy per extension,
/// so `O(extensions × types)`. Here each type is visited once up front and every later lookup is a
/// dictionary hit, with newly merged nested types registered as they arrive so a later extension can
/// still target them.
struct ExtensionTargetIndex {
    private struct Entry {
        let id: String
        let module: String
        /// Indices from the root through `nestedTypes`, for merging without searching.
        let path: [Int]
    }

    private(set) var types: [TypeDeclaration]
    private var entries: [Entry] = []
    /// A qualified name or id to the **earliest** type declaring it, matching the document-order
    /// `first(where:)` this replaces.
    private var entryByExactName: [String: Int] = [:]
    private var entriesBySimpleName: [String: [Int]] = [:]
    private var entriesByUnqualifiedID: [String: [Int]] = [:]

    init(types: [TypeDeclaration], counting counter: TypeFlattenCounter? = nil) {
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

    /// Merges `ext` into its target type anywhere in the tree, returning the target's id — or `nil`
    /// when the target is external, in which case the extension is dropped.
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

    /// The single type `name` should merge into: an exact id, else a sole same-module match, else a
    /// sole unqualified-id match; never a foreign simple name.
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
