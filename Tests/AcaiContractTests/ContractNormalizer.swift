import Foundation
import AcaiCore

/// Projects an enriched `CodeArtifact` onto the cross-language `ContractShape`, removing *only*
/// variation a language genuinely forces. Every rule below names the difference it exists for; none
/// of them may paper over a missing member, a missing edge or a wrong kind — that is the whole point
/// of the matrix, so a normalisation that could hide one does not belong here.
///
/// The rules:
/// 1. **Locations are dropped.** Each language's snippet is a different file at a different line.
/// 2. **Qualifiers are dropped.** A type is named by its simple name: Java requires a package, C++
///    idiomatically wraps a namespace, `std::string` is `.`-free but `::`-qualified, and Swift, Dart
///    and Python have no enclosing scope at all.
/// 3. **Constructors become one role.** `init`, `constructor`, `__init__` and `Song` are all the
///    language's spelling of the same construct, so the name is replaced by `<init>` and the role is
///    `constructor` (a destructor likewise).
/// 4. **Primitives and collections resolve through the language's own configuration** — never a table
///    in this test — so `Int`/`int`/`number`/`double` is `#primitive` and `[X]`/`List<X>`/
///    `std::vector<X>` is `#collection`.
/// 5. **Access becomes its UML symbol**, the closed vocabulary the diagram layer consumes: Swift
///    `internal` and Java package-private are the same `~`, `fileprivate` and `private` the same `-`.
/// 6. **A type's kind becomes its UML stereotype.** `TypeKind.stereotypeString` is how the diagram
///    layer names a kind, and it is the level at which a Swift `protocol` and a Java `interface` are
///    the same declaration. It still distinguishes `class` from `struct` from `enumeration`, so a
///    class mis-parsed as a struct is not hidden.
/// 7. **`open` is dropped from a type's and a member's modifiers, and `abstract` from an interface's.**
///    Inheritability is spelled by *presence* in Kotlin and Swift and by the *absence* of `final`
///    everywhere else, so the same inheritable class carries opposite markers; and an interface is
///    abstract by definition, which Dart's `abstract interface class` must say out loud and a Swift
///    `protocol` or Java `interface` must not. `abstract` on a *class* is kept. `static` is dropped
///    from a *nested type* for the same reason: a nested type that does not capture its enclosing
///    instance is `static class` in Java and an unmarked `class` in Kotlin, C++, Python and Swift.
///    `static` on a *member* is kept — that is a feature of its own.
/// 8. **An annotation that restates a modifier already present is dropped.** Java and Dart spell
///    override as `@override` *and* Kotlin/Swift/C++ as a keyword; Python spells abstract and static
///    as `@abstractmethod`/`@staticmethod`. The modifier is the shared fact, so the duplicate
///    annotation goes. An annotation with no matching modifier is always kept.
/// 9. **`suspend` reads as `async`.** Kotlin's keyword for a suspending function is the same
///    construct Swift, Python and JavaScript spell `async`; the closed `Modifier` enum keeps both
///    spellings, and only the matrix has to see them as one.
/// 10. **A private member's single leading underscore is dropped.** Dart and Python have no `private`
///    keyword; the underscore is it, so the same member is `shut` in Swift and `_shut` there. Applied
///    only where the parser already reports the member as private.
/// 11. **Declarations and edges are sorted**; parameters are not. C++ groups members by access section
///    and Python must declare `__init__` before it is used, so declaration order is not a shared
///    property — but parameter order is.
struct ContractNormalizer {
    let configuration: LanguageConfiguration

    static let primitiveToken = "#primitive"
    static let collectionToken = "#collection"
    static let constructorName = "<init>"
    static let destructorName = "<deinit>"

    func shape(of artifact: CodeArtifact) -> ContractShape {
        ContractShape(
            types: artifact.types.map { declaration(of: $0) }.sorted { $0.name < $1.name },
            freeFunctions: artifact.freestandingFunctions.map(signature(of:)).sorted(by: signatureOrder),
            globals: artifact.globalVariables.map(signature(of:)).sorted(by: signatureOrder),
            relationships: artifact.relationships.map(edge(of:)).sorted { lhs, rhs in
                (lhs.kind, lhs.source, lhs.target) < (rhs.kind, rhs.source, rhs.target)
            }
        )
    }

    // MARK: - Declarations

    private func declaration(of type: TypeDeclaration, isNested: Bool = false) -> ContractShape.Declaration {
        let isInterface = type.kind == .interface || type.kind == .protocol
        var implied: Set<Modifier> = isInterface ? [.open, .abstract] : [.open]
        if isNested { implied.insert(.static) }
        return ContractShape.Declaration(
            name: simpleName(type.name),
            kind: type.kind.stereotypeString ?? type.kind.rawValue,
            access: type.accessLevel.umlSymbol,
            modifiers: type.modifiers.filter { !implied.contains($0) }.map(\.rawValue).sorted(),
            generics: type.genericParameters.map { simpleName($0.name) },
            annotations: annotationNames(type.annotations, restating: type.modifiers),
            supertypes: type.inheritedTypes.map { typeName(of: $0) }.sorted(),
            members: type.members.map(signature(of:)).sorted(by: signatureOrder),
            enumCases: type.enumCases.map(\.name).sorted(),
            nested: type.nestedTypes
                .map { declaration(of: $0, isNested: true) }
                .sorted { $0.name < $1.name }
        )
    }

    private func signature(of member: Member) -> ContractShape.Signature {
        // A stored property's initializer expression is per-language — `[]` in Swift, `listOf()` in
        // Kotlin, absent in Java and C++ — so the calls it makes are not a shared property. A
        // *method*'s calls and reads are, which is where the call and read features live.
        let isStored = member.kind == .property && !member.isComputed
        return ContractShape.Signature(
            name: normalisedMemberName(member),
            role: member.kind.rawValue,
            access: member.accessLevel.umlSymbol,
            modifiers: member.modifiers
                .filter { $0 != .open }
                .map { ($0 == .suspend ? Modifier.async : $0).rawValue }
                .sorted(),
            annotations: annotationNames(member.annotations, restating: member.modifiers),
            type: member.type.map { typeName(of: $0) },
            parameters: member.parameters.map(parameter(of:)),
            calls: isStored ? [] : member.callSites.map(call(of:)).sorted(),
            reads: isStored ? [] : member.fieldReads.map { read in
                read.receiver.map { "\(simpleName($0)).\(read.name)" } ?? read.name
            }.sorted()
        )
    }

    private func signatureOrder(_ lhs: ContractShape.Signature, _ rhs: ContractShape.Signature) -> Bool {
        (lhs.role, lhs.name, lhs.parameters.joined(separator: ",")) <
            (rhs.role, rhs.name, rhs.parameters.joined(separator: ","))
    }

    /// Rule 3: a constructor is named after its type in Java/C++/Dart, `init` in Swift, `constructor`
    /// in TS/JS and `__init__` in Python — the `MemberKind` is what they share.
    private func normalisedMemberName(_ member: Member) -> String {
        switch member.kind {
        case .initializer:
            return Self.constructorName
        case .deinitializer:
            return Self.destructorName
        case .property, .method, .subscript:
            return privacyMarkerStripped(member.name, isPrivate: member.accessLevel == .private)
        }
    }

    /// Rule 10: Dart and Python have no `private` keyword — a leading underscore *is* the marker
    /// (Dart's `_x`, Python's name-mangled `__x`), so the same member is `shut` in Swift and `_shut` or
    /// `__shut` there. Applied only where the parser already reports the member as private.
    private func privacyMarkerStripped(_ name: String, isPrivate: Bool) -> String {
        guard isPrivate else { return name }
        return String(name.drop(while: { $0 == "_" }))
    }

    private func parameter(of parameter: Parameter) -> String {
        let type = parameter.type.map { typeName(of: $0) } ?? "?"
        let suffix = parameter.defaultValue == nil ? "" : " = …"
        return "\(parameter.internalName): \(type)\(suffix)"
    }

    private func call(of site: CallSite) -> String {
        switch site.receiver {
        case .selfDispatch:
            return ".\(site.methodName)"
        case .type(let name):
            return "\(simpleName(name)).\(site.methodName)"
        case .unresolvedTypeName(let name):
            return "?\(simpleName(name)).\(site.methodName)"
        case .free:
            return "\(site.methodName)()"
        case .propertyChain(let head, let hops):
            return ([simpleName(head)] + hops + [site.methodName]).joined(separator: ".")
        case .ownProperty(let property, let hops):
            return (["self", property] + hops + [site.methodName]).joined(separator: ".")
        case .ownPropertyElement(let property):
            return "self.\(property)[].\(site.methodName)"
        case .ownMethodReturn(let method, let hops):
            return (["self", "\(method)()"] + hops + [site.methodName]).joined(separator: ".")
        case .unknown:
            return "?.\(site.methodName)"
        }
    }

    private func edge(of relationship: Relationship) -> ContractShape.Edge {
        ContractShape.Edge(
            kind: relationship.kind.rawValue,
            source: simpleName(relationship.source),
            target: simpleName(relationship.target),
            label: relationship.label,
            multiplicity: relationship.targetLabel ?? relationship.sourceLabel
        )
    }

    // MARK: - Names

    /// Rule 4, then rule 2: classification runs on the name the parser produced (a C++ primitive is
    /// spelled `std::string`), and only what survives it is reduced to a simple name.
    func typeName(of reference: TypeReference) -> String {
        let optional = reference.isOptional ? "?" : ""
        let base = classify(reference.name)
        guard base == Self.collectionToken || reference.isArray else { return base + optional }
        var elements = reference.genericArguments.map { typeName(of: $0) }
        // `Item[]` names its element in `name` with no generic arguments; `List<Item>` the other way.
        if elements.isEmpty, base != Self.collectionToken { elements = [base] }
        let inner = elements.isEmpty ? "" : "<\(elements.joined(separator: ","))>"
        return Self.collectionToken + inner + optional
    }

    private func classify(_ name: String) -> String {
        if configuration.isPrimitive(name) { return Self.primitiveToken }
        if configuration.isCollectionType(name) { return Self.collectionToken }
        let simple = simpleName(name)
        if configuration.isPrimitive(simple) { return Self.primitiveToken }
        if configuration.isCollectionType(simple) { return Self.collectionToken }
        return simple
    }

    private func simpleName(_ name: String) -> String {
        name.replacingOccurrences(of: "::", with: ".").components(separatedBy: ".").last ?? name
    }

    /// Kotlin/Java write `@Deprecated`, Python `@dataclass`, Dart `@override`, TypeScript `@Component()`
    /// — the marker is the name, not its punctuation or argument list.
    private func annotationName(of annotation: String) -> String {
        let withoutAt = annotation.hasPrefix("@") ? String(annotation.dropFirst()) : annotation
        let withoutArguments = withoutAt.components(separatedBy: "(").first ?? withoutAt
        return simpleName(withoutArguments.trimmingCharacters(in: .whitespaces))
    }

    /// Rule 8: `@abstractmethod` beside `.abstract`, `@override` beside `.override` — the annotation is
    /// the language's spelling of a modifier already recorded, so only the modifier survives. The
    /// `method`/`property` suffix covers Python's `@staticmethod`/`@abstractmethod`.
    private func annotationNames(_ annotations: [String], restating modifiers: [Modifier]) -> [String] {
        let present = Set(modifiers.map { $0.rawValue.lowercased() })
        return annotations
            .map(annotationName(of:))
            .filter { name in
                let lowered = name.lowercased()
                let stem = ["method", "property"].reduce(lowered) { stem, suffix in
                    stem.hasSuffix(suffix) ? String(stem.dropLast(suffix.count)) : stem
                }
                return !present.contains(lowered) && !present.contains(stem)
            }
            .sorted()
    }
}
