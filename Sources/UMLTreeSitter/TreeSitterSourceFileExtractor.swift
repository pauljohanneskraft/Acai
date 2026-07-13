import Foundation
@preconcurrency import SwiftTreeSitter
import UMLCore

/// The one orchestrator a `CodeParser.parse` calls. Contains no extraction logic of its own — only
/// sequencing of the collaborators in this package — so it stays a thin facade, not a god class.
public struct TreeSitterSourceFileExtractor: Sendable {
    private let plugin: TreeSitterLanguagePlugin

    public init(plugin: TreeSitterLanguagePlugin) {
        self.plugin = plugin
    }

    public func extract(source sourceText: String, fileName: String) -> CodeArtifact {
        let parser = SourceFileParser(language: plugin.grammar)
        guard let source = parser.parse(source: sourceText, fileName: fileName) else {
            return CodeArtifact(metadata: .init(
                sourceLanguage: plugin.sourceLanguage, filePaths: [fileName],
                parseDiagnostics: [ParseDiagnostic(
                    location: SourceLocation(filePath: fileName, line: 1, column: 1), kind: .error,
                    message: "Failed to parse with the \(plugin.sourceLanguage.rawValue) tree-sitter grammar.")]))
        }

        let matches = plugin.structuralQuery.matches(in: source)
        // A decorated declaration matches both a bare pattern and a decorator-wrapped one (the
        // decorated node still satisfies the bare shape too) — keep one match per underlying node.
        let typeMatches = dedupedByCaptureNode(matches.filter { !$0.captures(named: "type").isEmpty }, captureName: "type")
        let memberMatches = dedupedByCaptureNode(matches.filter { !$0.captures(named: "member").isEmpty }, captureName: "member")
        let enumCaseMatches = matches.filter { !$0.captures(named: "enumCase").isEmpty }
        if ProcessInfo.processInfo.environment["UML_DEBUG_QUERY"] != nil {
            print("TOTAL matches: \(matches.count)")
            for match in matches {
                let names = match.captures.compactMap(\.name).joined(separator: ", ")
                print("  match pattern=\(match.patternIndex) captures=[\(names)]")
            }
        }

        let typeNodes = typeMatches.map { RangedNode($0.capture(named: "type")!.node) }
        let declaredTypeNames = Set(typeMatches.compactMap { $0.capture(named: "type.name")?.node.text(in: source) })

        let valueClassifier = LiteralValueClassifier(grammar: plugin.expressionGrammar, literals: plugin.literals)
        let assembledMembers = MemberSignatureAssembler(
            vocabulary: plugin.vocabulary, typeReference: plugin.typeReference, valueClassifier: valueClassifier
        ).assemble(memberMatches, source: source)
        let assembledEnumCases = EnumCaseAssembler().assemble(enumCaseMatches, source: source)

        let memberGroups = groupedByInnermostType(assembledMembers, typeNodes: typeNodes)
        let enumCaseGroups = groupedByInnermostType(assembledEnumCases, typeNodes: typeNodes)

        let walker = MemberBodyWalker(grammar: plugin.expressionGrammar, literals: plugin.literals)
        let complexity = CyclomaticComplexityCounter(grammar: plugin.expressionGrammar)

        var membersByType: [Int: [Member]] = [:]
        for (typeIndex, group) in memberGroups.byType {
            let index = KnownMemberIndex(members: group.map(\.member), knownTypeNames: declaredTypeNames)
            membersByType[typeIndex] = group.map { analyzeBody(of: $0, index: index, source: source, walker: walker, complexity: complexity) }
        }
        let enumCasesByType = enumCaseGroups.byType.mapValues { $0.map(\.enumCase) }

        let moduleIndex = KnownMemberIndex(members: [], knownTypeNames: declaredTypeNames)
        var topLevelMembers = memberGroups.topLevel.map {
            analyzeBody(of: $0, index: moduleIndex, source: source, walker: walker, complexity: complexity)
        }
        if let syntheticTopLevel = syntheticTopLevelMember(source: source, index: moduleIndex, walker: walker) {
            topLevelMembers.append(syntheticTopLevel)
        }

        let (types, relationships) = TypeDeclarationAssembler(vocabulary: plugin.vocabulary).assemble(
            typeMatches: typeMatches, membersByType: membersByType, enumCasesByType: enumCasesByType, source: source)

        let diagnostics = source.rootNode.hasError ? ParseDiagnosticsCollector().diagnostics(in: source) : []

        return CodeArtifact(
            metadata: .init(sourceLanguage: plugin.sourceLanguage, filePaths: [fileName], parseDiagnostics: diagnostics),
            types: types,
            relationships: relationships,
            freestandingFunctions: topLevelMembers.filter { $0.kind != .property },
            globalVariables: topLevelMembers.filter { $0.kind == .property })
    }

    /// Runs body analysis for one already-assembled member, when it captured a body, and folds the
    /// result into its `Member` value.
    private func analyzeBody(
        of assembled: AssembledMember, index: KnownMemberIndex, source: ParsedSource,
        walker: MemberBodyWalker, complexity: CyclomaticComplexityCounter
    ) -> Member {
        guard let body = assembled.bodyNode else { return assembled.member }
        var member = assembled.member
        let scoped = index.merging(parameters: member.parameters)
        let result = walker.walk(body: body, source: source, index: scoped)
        member.callSites = result.callSites
        member.assignments = result.assignments
        member.fieldReads = result.fieldReads
        member.referencedTypeNames = result.referencedTypeNames
        member.cyclomaticComplexity = complexity.count(body: body)
        return member
    }

    /// RC-H: collects call sites made directly by bare top-level statements (per
    /// `plugin.topLevelCallNodePredicate`) into one synthetic, always-reachable `<top-level>` member,
    /// so a bootstrap-style call (`main()`, `if __name__ == "__main__":`) doesn't leave its target
    /// looking unreachable to dead-code analysis. `nil` when the language has none of these, or none
    /// were found.
    private func syntheticTopLevelMember(
        source: ParsedSource, index: KnownMemberIndex, walker: MemberBodyWalker
    ) -> Member? {
        guard let predicate = plugin.topLevelCallNodePredicate else { return nil }
        let callSites = source.rootNode.children().filter(predicate)
            .flatMap { walker.walk(body: $0, source: source, index: index).callSites }
        guard !callSites.isEmpty else { return nil }
        return Member(name: "<top-level>", kind: .method, accessLevel: .public, callSites: callSites)
    }
}
