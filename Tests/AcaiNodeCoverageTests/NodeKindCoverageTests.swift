import Testing

/// Holds every Tree-sitter plugin to a checked-in classification of the node kinds its corpus
/// produces, so syntax an extractor silently drops surfaces as an unclassified kind rather than as
/// a declaration nobody notices is missing.
///
/// The inventories live here, in the test target, never in an agnostic one: they are a statement
/// about what each *extractor* handles, not data the engine reads.
@Suite("Extractor node-kind coverage")
struct NodeKindCoverageTests {

    @Test("every node kind the corpus produces is classified", arguments: NodeKindCorpus().plugins)
    func everyKindIsClassified(plugin: NodeKindCorpus.Plugin) throws {
        let corpus = NodeKindCorpus()
        let sources = corpus.sources(for: plugin)
        try #require(!sources.isEmpty, "the corpus holds no \(plugin.stem) source")

        var unclassified: Set<String> = []
        var unreadableNames: Set<String> = []
        for source in sources {
            let facts = try corpus.facts(of: source, plugin: plugin)
            #expect(!facts.hasParseError, "\(source) does not parse cleanly, so its kinds say nothing")
            unclassified.formUnion(facts.kinds.filter { !plugin.inventory.classifies($0) })
            unreadableNames.formUnion(facts.unreadableNames)
        }

        #expect(
            unclassified.isEmpty,
            """
            \(plugin.stem) produces node kinds no inventory entry covers: \
            \(unclassified.sorted().joined(separator: ", ")).
            Classify each in \(plugin.stem.capitalized)NodeKinds as extracted, ignored with a reason, \
            or not a declaration.
            """
        )
        #expect(
            unreadableNames.isEmpty,
            """
            \(plugin.stem)'s inventory calls these kinds extracted but its `NamePath` reads no name \
            from them: \(unreadableNames.sorted().joined(separator: ", ")).
            """
        )
    }

    @Test("every node of an extracted kind yields a declaration", arguments: NodeKindCorpus().plugins)
    func extractedKindsYieldDeclarations(plugin: NodeKindCorpus.Plugin) throws {
        let corpus = NodeKindCorpus()
        for source in corpus.sources(for: plugin) {
            let declarations = try corpus.declarations(of: source, plugin: plugin)
            for occurrence in try corpus.facts(of: source, plugin: plugin).occurrences {
                guard let kind = plugin.inventory.extracted[occurrence.kind] else { continue }
                check(occurrence, against: declarations, expecting: kind.expectation(inside: occurrence.enclosing),
                      in: source)
            }
        }
    }

    /// Every kind an inventory calls extracted has to occur in the corpus: a kind spelled wrong, or
    /// one no fixture reaches, makes the assertion above pass without checking anything.
    @Test("every extracted kind occurs in the corpus", arguments: NodeKindCorpus().plugins)
    func everyExtractedKindOccurs(plugin: NodeKindCorpus.Plugin) throws {
        let corpus = NodeKindCorpus()
        var seen: Set<String> = []
        for source in corpus.sources(for: plugin) {
            seen.formUnion(try corpus.facts(of: source, plugin: plugin).kinds)
        }
        let absent = Set(plugin.inventory.extracted.keys).subtracting(seen)
        #expect(
            absent.isEmpty,
            """
            \(plugin.stem)'s inventory claims these extracted kinds, which no corpus source produces: \
            \(absent.sorted().joined(separator: ", ")). Add a fixture reaching each, or drop it.
            """
        )
    }

    private func check(
        _ occurrence: NodeKindCorpus.Occurrence,
        against declarations: DeclarationIndex,
        expecting expectation: ExtractedKind.Expectation,
        in source: NodeKindCorpus.Source
    ) {
        let found = declarations.declaresName(occurrence.name, onAnyLineIn: occurrence.headerLines)
        let detail = """
        \(source) declares \(occurrence.kind) '\(occurrence.name)' on line \
        \(occurrence.headerLines.lowerBound), and the parser extracted nothing by that name there.
        """
        switch expectation {
        case .ignored:
            break
        case .declared:
            #expect(found, Comment(rawValue: detail))
        case .knownGap(let issue):
            withKnownIssue("\(occurrence.kind) is dropped — \(issue)") {
                #expect(found, Comment(rawValue: detail))
            }
        }
    }
}
