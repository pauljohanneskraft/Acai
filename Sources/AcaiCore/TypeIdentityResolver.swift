import Foundation

/// A resolved, canonical type identity — a declared type's fully-qualified id (equal to its
/// ``TypeDeclaration/qualifiedName``). A distinct type from a bare simple name so the two identity
/// formats can't be silently confused at a resolution boundary.
public struct TypeID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The canonical id string (a type's fully-qualified id).
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }
}

/// The outcome of resolving a referenced type name against an artifact's declared types.
///
/// Distinguishing these three cases is the point of #88: a reference that *matched several types*
/// (ambiguous) is a likely-actionable defect, whereas one that *matched nothing* (external) is the
/// normal case for stdlib/third-party supertypes. Both degrade transparently — ``canonicalName``
/// carries the original string through — but only the ambiguous case warrants a diagnostic.
public enum ResolvedTypeIdentity: Hashable, Sendable {
    /// The name matched a declared type (by id, qualified name, or a globally-unambiguous simple name).
    case resolved(TypeID)
    /// The simple name is shared by two or more declared types (none of which is a top-level type
    /// whose qualified name equals it), so it is left unresolved rather than bound to an arbitrary one.
    case ambiguous(String)
    /// The name matched no declared type — an external/unknown reference, carried through as-is.
    case external(String)

    /// The canonical string used when rewriting a relationship endpoint or supertype name: the
    /// resolved id, or the original name for ambiguous/external references (transparent degradation,
    /// preserving existing output).
    public var canonicalName: String {
        switch self {
        case .resolved(let id):
            return id.value
        case .ambiguous(let name), .external(let name):
            return name
        }
    }
}

/// The single authority for resolving a type reference's name to a canonical type id.
///
/// Type identity flows through the engine as bare `String`s in three interchangeable formats — a
/// declared type's `id` / `qualifiedName` (fully qualified) and its simple `name`. This resolver
/// centralises the name→id mapping and its ambiguity rule (a simple name resolves only when it is
/// globally unique across all declared types, nested included) that was previously duplicated across
/// enrichment and the tree-sitter extractors, so every layer resolves identity the same way. Build
/// it once from an artifact's `types`, then resolve names against it.
public struct TypeIdentityResolver: Sendable {
    private let idByName: [String: String]
    private let ambiguousSimpleNames: Set<String>

    public init(types: [TypeDeclaration]) {
        var exactKeyCount: [String: Int] = [:]
        var exactKeyID: [String: String] = [:]
        var simpleNameCount: [String: Int] = [:]

        // Counts each exact key (id + qualified name) rather than mapping it unconditionally: a
        // top-level type's qualified name equals its bare name, so two top-level types sharing a
        // name collide *here*, not just at the simple-name tier below — a collision must not
        // silently resolve to whichever type was counted last.
        func countKeys(_ types: [TypeDeclaration]) {
            for type in types {
                for key in Set([type.id, type.qualifiedName]) {
                    exactKeyCount[key, default: 0] += 1
                    exactKeyID[key] = type.id
                }
                let simple = type.name.components(separatedBy: ".").last ?? type.name
                simpleNameCount[simple, default: 0] += 1
                countKeys(type.nestedTypes)
            }
        }
        countKeys(types)

        var idByName: [String: String] = [:]
        for (key, count) in exactKeyCount where count == 1 {
            idByName[key] = exactKeyID[key]
        }

        // Simple names map only when globally unambiguous and not already an exact key — mapping an
        // ambiguous nested name would fabricate spurious edges to whichever type was indexed last.
        func indexSimple(_ types: [TypeDeclaration]) {
            for type in types {
                let simple = type.name.components(separatedBy: ".").last ?? type.name
                if simpleNameCount[simple] == 1, idByName[simple] == nil {
                    idByName[simple] = type.id
                }
                indexSimple(type.nestedTypes)
            }
        }
        indexSimple(types)

        self.idByName = idByName
        self.ambiguousSimpleNames = Set(simpleNameCount.filter { $0.value > 1 }.keys)
            .union(exactKeyCount.filter { $0.value > 1 }.keys)
    }

    /// Resolves a referenced type name (generics stripped by the caller where relevant) to a
    /// canonical identity.
    public func resolve(_ name: String) -> ResolvedTypeIdentity {
        if let id = idByName[name] { return .resolved(TypeID(id)) }
        if ambiguousSimpleNames.contains(name) { return .ambiguous(name) }
        return .external(name)
    }

    /// The canonical id string for `name` — the resolved id, or `name` unchanged when it is ambiguous
    /// or external. Convenience for the common "rewrite to id, else leave as-is" resolution path.
    public func canonicalName(for name: String) -> String {
        resolve(name).canonicalName
    }

    /// The canonical id for `name` **only** when it resolves to a declared type; `nil` for ambiguous
    /// or external names. Use where an unknown reference must be skipped (e.g. coupling metrics count
    /// edges only to known types) rather than carried through.
    public func resolvedID(for name: String) -> TypeID? {
        if case .resolved(let id) = resolve(name) { return id }
        return nil
    }
}
