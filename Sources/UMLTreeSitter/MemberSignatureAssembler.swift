@preconcurrency import SwiftTreeSitter
import UMLCore

/// A member assembled from one `@member` query match, alongside the plumbing the rest of extraction
/// still needs: its source range (for attributing it to the innermost enclosing `@type`) and its
/// `@member.body` node, if captured (handed to body analysis once the member's enclosing type's
/// sibling members are known).
struct AssembledMember: Sendable {
    var member: Member
    var range: Range<UInt32>
    var bodyNode: Node?
}

/// `@member.*` captures → `[AssembledMember]` (signature only — no body analysis; that's
/// `MemberBodyWalker`). A language plugin's query supplies the shape; this assembler is identical
/// for every language.
struct MemberSignatureAssembler: Sendable {
    private let vocabulary: TypeStructureVocabulary
    private let typeReference: TypeReferenceResolver
    private let valueClassifier: LiteralValueClassifier

    init(vocabulary: TypeStructureVocabulary, typeReference: TypeReferenceResolver, valueClassifier: LiteralValueClassifier) {
        self.vocabulary = vocabulary
        self.typeReference = typeReference
        self.valueClassifier = valueClassifier
    }

    func assemble(_ matches: [QueryMatch], source: ParsedSource) -> [AssembledMember] {
        matches.compactMap { assemble($0, source: source) }
    }

    private func assemble(_ match: QueryMatch, source: ParsedSource) -> AssembledMember? {
        guard let memberCapture = match.capture(named: "member"),
              let nameCapture = match.capture(named: "member.name")
        else { return nil }

        // A member's kind is usually a captured keyword node (`@member.kind`, mapped by text); a
        // shape with no keyword at all — Python's class-body/`self.x` field patterns, which are
        // plain assignments — instead tags its kind directly via a match-level `(#set! member.kind
        // "property")` directive, read here as a fallback.
        let kind = match.capture(named: "member.kind").flatMap { MemberKind(rawValue: $0.node.text(in: source)) }
            ?? match.metadata["member.kind"].flatMap { MemberKind(rawValue: $0) }
            ?? .method
        let access = match.capture(named: "member.access")
            .flatMap { vocabulary.accessKeywords[$0.node.text(in: source)] } ?? vocabulary.defaultAccessLevel
        let setAccess = match.capture(named: "member.setAccess")
            .flatMap { vocabulary.accessKeywords[$0.node.text(in: source)] }
        let modifiers = match.captures(named: "member.modifier")
            .compactMap { vocabulary.modifierKeywords[$0.node.text(in: source)] }
        let type = match.capture(named: "member.type").map { typeReference($0.node, in: source) }
        let annotations = match.captures(named: "member.annotation").map { $0.node.text(in: source) }
        let isComputed = match.capture(named: "member.computed") != nil
        let generics = match.captures(named: "member.generic.param")
            .map { GenericParameter(name: $0.node.text(in: source)) }
        let parameters = assembleParameters(match, source: source)
        let initialValueCapture = match.capture(named: "member.initialValue")
        // A property with no body of its own still has an initializer expression that can contain
        // calls worth capturing (`x = compute()`) — walking it through the same body-analysis
        // pipeline as a real body needs no special-casing beyond treating it as one.
        let bodyNode = match.capture(named: "member.body")?.node ?? initialValueCapture?.node
        let initialValue = initialValueCapture.map { valueClassifier.classify($0.node, in: source) }

        let member = Member(
            name: nameCapture.node.text(in: source),
            kind: kind,
            accessLevel: access,
            setAccessLevel: setAccess,
            modifiers: modifiers,
            type: type,
            parameters: parameters,
            genericParameters: generics,
            isComputed: isComputed,
            annotations: annotations,
            location: memberCapture.node.location(in: source),
            initialValue: initialValue
        )
        return AssembledMember(member: member, range: memberCapture.node.byteRange, bodyNode: bodyNode)
    }

    /// Groups `@member.param.*` sub-captures by their containing `@member.param` node (a parameter's
    /// own fields are descendants of its container node — the same containment relationship used
    /// elsewhere to attribute a member to its enclosing type).
    private func assembleParameters(_ match: QueryMatch, source: ParsedSource) -> [Parameter] {
        let containers = match.captures(named: "member.param").map { RangedNode($0.node) }
        guard !containers.isEmpty else { return [] }

        let externalNames = match.captures(named: "member.param.external")
        let names = match.captures(named: "member.param.name")
        let types = match.captures(named: "member.param.type")
        let defaults = match.captures(named: "member.param.default")
        let variadics = match.captures(named: "member.param.variadic")

        return containers.map { container in
            let name = names.first { container.range.contains($0.node.byteRange) }
                .map { $0.node.text(in: source) } ?? ""
            let external = externalNames.first { container.range.contains($0.node.byteRange) }
                .map { $0.node.text(in: source) }
            let paramType = types.first { container.range.contains($0.node.byteRange) }
                .map { typeReference($0.node, in: source) }
            let defaultValue = defaults.first { container.range.contains($0.node.byteRange) }
                .map { $0.node.text(in: source) }
            let isVariadic = variadics.contains { container.range.contains($0.node.byteRange) }
            return Parameter(
                externalName: external, internalName: name, type: paramType,
                defaultValue: defaultValue, isVariadic: isVariadic)
        }
    }
}

extension Range where Bound == UInt32 {
    /// Whether `other` falls entirely within `self` (used to attribute a parameter's sub-captures to
    /// its own container node, and — with the same semantics — a member/enum-case/nested-type to its
    /// innermost enclosing type).
    func contains(_ other: Range<UInt32>) -> Bool {
        lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }
}
