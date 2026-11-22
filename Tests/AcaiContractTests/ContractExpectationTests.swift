import Foundation
import Testing

@Suite("Contract expectation allowances")
struct ContractExpectationTests {

    private func shape(
        kind: String = "class", type: String? = "#primitive", parameters: [String] = ["id: #primitive"]
    ) -> ContractShape {
        ContractShape(types: [
            ContractShape.Declaration(
                name: "Box", kind: kind, access: "+",
                members: [
                    ContractShape.Signature(
                        name: "size", role: "method", access: "+", type: type, parameters: parameters)
                ],
                nested: [ContractShape.Declaration(name: "Inner", kind: kind, access: "+")])
        ])
    }

    @Test("an unchecked type drops a signature's own type and its parameters' on both sides")
    func uncheckedTypeIsComparedOnNeitherSide() {
        let allowance = ContractExpectation.LanguageAllowance(unchecked: [.type])
        let expected = allowance.expected(shape())
        let actual = allowance.actual(shape(type: nil, parameters: ["id: ?"]))
        #expect(expected == actual)
        let member = expected.types[0].members[0]
        #expect(member.type == nil)
        #expect(member.parameters == ["id: #unchecked"])
        // The parameter's *name* is still compared — only its type is excused.
        #expect(allowance.actual(shape(type: nil, parameters: ["other: ?"])) != expected)
    }

    @Test("an unchecked kind drops the stereotype of a nested declaration too")
    func uncheckedKindReachesNestedDeclarations() {
        let allowance = ContractExpectation.LanguageAllowance(unchecked: [.kind])
        let expected = allowance.expected(shape())
        #expect(expected.types[0].kind == "#unchecked")
        #expect(expected.types[0].nested[0].kind == "#unchecked")
        #expect(expected == allowance.actual(shape(kind: "struct")))
    }

    @Test("a mapped kind is applied to the expectation, so the language's own kind is still checked")
    func mappedKindStillChecksTheLanguage() {
        let allowance = ContractExpectation.LanguageAllowance(typeKinds: ["class": "struct"])
        let expected = allowance.expected(shape())
        #expect(expected.types[0].kind == "struct")
        #expect(expected.types[0].nested[0].kind == "struct")
        #expect(expected == allowance.actual(shape(kind: "struct")))
        // A language that reports the kind the expectation named, rather than its own, still fails.
        #expect(expected != allowance.actual(shape()))
    }

    @Test("an allowance cannot hide a missing member, a wrong role or a lost edge")
    func anAllowanceOnlyNarrowsOneField() {
        let allowance = ContractExpectation.LanguageAllowance(
            unchecked: [.type, .kind], typeKinds: ["class": "struct"])
        let expected = allowance.expected(shape())
        #expect(expected != allowance.actual(ContractShape(types: [
            ContractShape.Declaration(name: "Box", kind: "class", access: "+")
        ])))
        var wrongRole = shape(type: nil, parameters: ["id: ?"])
        wrongRole.types[0].members[0].role = "property"
        #expect(expected != allowance.actual(wrongRole))
        var extraEdge = shape(type: nil, parameters: ["id: ?"])
        extraEdge.relationships = [ContractShape.Edge(kind: "dependency", source: "Box", target: "Inner")]
        #expect(expected != allowance.actual(extraEdge))
    }

    @Test("the shape and its allowances share the expectation's top-level object")
    func expectationDecodesShapeAndAllowancesTogether() throws {
        let json = """
        {
          "types": [{ "name": "Box", "kind": "class", "access": "+" }],
          "languages": { "c": { "typeKinds": { "class": "struct" }, "unchecked": ["type"] } }
        }
        """
        let expectation = try JSONDecoder().decode(ContractExpectation.self, from: Data(json.utf8))
        #expect(expectation.shape.types.map(\.name) == ["Box"])
        #expect(expectation.languages["c"]?.typeKinds == ["class": "struct"])
        #expect(expectation.languages["c"]?.unchecked == [.type])
    }

    @Test("a feature with no allowances compares every language against the shape as written")
    func absentAllowancesLeaveTheShapeAlone() throws {
        let json = """
        { "types": [{ "name": "Box", "kind": "class", "access": "+" }] }
        """
        let expectation = try JSONDecoder().decode(ContractExpectation.self, from: Data(json.utf8))
        #expect(expectation.languages.isEmpty)
        let allowance = ContractExpectation.LanguageAllowance()
        #expect(allowance.isEmpty)
        #expect(allowance.expected(shape()) == shape())
        #expect(allowance.actual(shape()) == shape())
    }

    @Test("a backticked or covered-by kebab-case token reads as a feature citation, prose does not")
    func citationsAreRecognised() {
        let corpus = ContractFeatureCorpus()
        #expect(corpus.citedFeatures(in: "covered by `interface-conformance`.") == ["interface-conformance"])
        #expect(
            corpus.citedFeatures(
                in: "Kotlin has no static member; the idiom is a companion object, which declares a nested type "
                    + "holding the member rather than a static member on the class, and is covered by "
                    + "companion-extension.")
                == ["companion-extension"])
        #expect(corpus.citedFeatures(in: "carries no return-type annotation, so it is top-level.").isEmpty)
        #expect(corpus.citedFeatures(in: "`static` on a file-scope function means linkage.").isEmpty)
        #expect(corpus.citedFeatures(in: "`std::vector<Item>` is a `List<X>`.").isEmpty)
    }
}
