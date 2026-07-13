@preconcurrency import SwiftTreeSitter
import UMLCore

/// `@type.*` captures → `[TypeDeclaration]`, including nesting (by capture byte-range containment —
/// a `@type` capture whose range is inside another's is a nested type, prefixed by the parent's id)
/// and the id == qualifiedName producer-contract invariant (`Sources/UMLCore/CodeParser.swift`).
struct TypeDeclarationAssembler: Sendable {
    private let vocabulary: TypeStructureVocabulary

    init(vocabulary: TypeStructureVocabulary) {
        self.vocabulary = vocabulary
    }

    /// - Parameters:
    ///   - typeMatches: every `@type` query match in the file. **Precondition:** every match here
    ///     already has a `"type"` capture (the caller filters for this) — `membersByType`/
    ///     `enumCasesByType` are keyed by index into this exact array, computed by the caller against
    ///     the same array, so the two must stay in lockstep.
    ///   - membersByType: each type match's already body-analyzed members, keyed by that match's
    ///     index in `typeMatches`.
    ///   - enumCasesByType: likewise for enum cases.
    /// - Returns: the top-level (non-nested) type declarations (each with its nested types attached),
    ///   plus the inheritance/conformance `Relationship`s derived from every type's supertypes (the
    ///   agnostic enrichment pass only derives relationships from *extensions*, so ordinary
    ///   supertypes need an explicit edge here — see `CodeArtifact.resolvingExtensions()`).
    func assemble(
        typeMatches: [QueryMatch],
        membersByType: [Int: [Member]],
        enumCasesByType: [Int: [EnumCase]],
        source: ParsedSource
    ) -> (types: [TypeDeclaration], relationships: [Relationship]) {
        let records = typeMatches.map { TypeRecord($0, vocabulary: vocabulary, source: source) }
        let typeNodes = records.map { RangedNode($0.node) }
        let parents = typeNodes.indices.map { innermostContainerIndex(containing: typeNodes[$0].range, in: typeNodes) }

        var childrenByParent: [Int: [Int]] = [:]
        var roots: [Int] = []
        for index in records.indices {
            if let parent = parents[index] {
                childrenByParent[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort { typeNodes[$0].range.lowerBound < typeNodes[$1].range.lowerBound }
        }
        roots.sort { typeNodes[$0].range.lowerBound < typeNodes[$1].range.lowerBound }

        var relationships: [Relationship] = []

        func build(_ index: Int, qualifiedPrefix: String?) -> TypeDeclaration {
            let record = records[index]
            let qualifiedName = qualifiedPrefix.map { "\($0).\(record.name)" }
                ?? record.namespace.map { "\($0).\(record.name)" } ?? record.name
            for supertype in record.supertypes {
                relationships.append(Relationship(kind: supertype.kind, source: qualifiedName, target: supertype.reference.name))
            }
            let nested = (childrenByParent[index] ?? []).map { build($0, qualifiedPrefix: qualifiedName) }
            return TypeDeclaration(
                id: qualifiedName, name: record.name, qualifiedName: qualifiedName, kind: record.kind,
                accessLevel: record.access, modifiers: record.modifiers,
                genericParameters: record.generics, inheritedTypes: record.supertypes.map(\.reference),
                members: membersByType[index] ?? [], enumCases: enumCasesByType[index] ?? [],
                nestedTypes: nested, annotations: record.annotations,
                extensionOf: record.extensionOf, namespace: qualifiedPrefix == nil ? record.namespace : nil,
                location: record.location)
        }

        let types = roots.map { build($0, qualifiedPrefix: nil) }
        return (types, relationships)
    }
}

/// One captured supertype, tagged with the `Relationship.Kind` it draws — read from the capture's
/// `#set! type.supertype.kind "conformance"` metadata (defaulting to `.inheritance` when a
/// language's query doesn't distinguish the two, e.g. Python's positional base-class list).
private struct SupertypeRecord {
    let reference: TypeReference
    let kind: Relationship.Kind

    init(_ capture: QueryCapture, source: ParsedSource) {
        reference = TypeReference(name: SimpleTypeName(capture.node.text(in: source)).simpleName)
        kind = capture.metadata["kind"] == "conformance" ? .conformance : .inheritance
    }
}

/// The immediate (non-nesting) facts read off one `@type` match, before the recursive tree is built.
private struct TypeRecord {
    let node: Node
    let name: String
    let kind: TypeKind
    let access: AccessLevel
    let modifiers: [Modifier]
    let supertypes: [SupertypeRecord]
    let generics: [GenericParameter]
    let annotations: [String]
    let namespace: String?
    let extensionOf: String?
    let location: SourceLocation

    /// - Precondition: `match` has a `"type"` capture (the caller only passes matches that do).
    init(_ match: QueryMatch, vocabulary: TypeStructureVocabulary, source: ParsedSource) {
        node = match.capture(named: "type")!.node
        name = match.capture(named: "type.name")?.node.text(in: source) ?? ""
        kind = match.capture(named: "type.kind")
            .flatMap { vocabulary.kindKeywords[$0.node.text(in: source)] } ?? .class
        access = match.capture(named: "type.access")
            .flatMap { vocabulary.accessKeywords[$0.node.text(in: source)] } ?? vocabulary.defaultAccessLevel
        modifiers = match.captures(named: "type.modifier")
            .compactMap { vocabulary.modifierKeywords[$0.node.text(in: source)] }
        supertypes = match.captures(named: "type.supertype").map { SupertypeRecord($0, source: source) }
        generics = match.captures(named: "type.generic.param")
            .map { GenericParameter(name: $0.node.text(in: source)) }
        annotations = match.captures(named: "type.annotation").map { $0.node.text(in: source) }
        namespace = match.capture(named: "type.namespace")?.node.text(in: source)
        extensionOf = match.capture(named: "type.extensionOf")
            .map { SimpleTypeName($0.node.text(in: source)).simpleName }
        location = node.location(in: source)
    }
}
