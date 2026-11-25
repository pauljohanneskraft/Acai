import Testing

/// Holds each plugin to a checked-in classification of the node kinds its corpus produces.
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
            Classify each in \(plugin.stem)'s inventory as extracted, ignored with a reason, \
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

    /// Without an occurrence apiece, the assertion above passes without checking anything.
    @Test("every extracted kind occurs in the corpus", arguments: NodeKindCorpus().plugins)
    func everyExtractedKindOccurs(plugin: NodeKindCorpus.Plugin) throws {
        let corpus = NodeKindCorpus()
        var named: Set<String> = []
        for source in corpus.sources(for: plugin) {
            named.formUnion(try corpus.facts(of: source, plugin: plugin).occurrences.map(\.kind))
        }
        let absent = Set(plugin.inventory.extracted.keys).subtracting(named)
        #expect(
            absent.isEmpty,
            """
            \(plugin.stem)'s inventory claims these extracted kinds, which no corpus source declares a \
            name for: \(absent.sorted().joined(separator: ", ")). Add a fixture reaching each, fix its \
            `NamePath`, or drop it.
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
            withKnownIssue("\(occurrence.kind) is not extracted on its own line — \(issue)") {
                #expect(found, Comment(rawValue: detail))
            }
        }
    }
}
