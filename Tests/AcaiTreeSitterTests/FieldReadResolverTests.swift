import AcaiCore
import Testing
@testable import AcaiTreeSitter

@Suite("Field Read Resolver")
struct FieldReadResolverTests {

    private let source = """
    class Service {
        void run() {
            int local = count;
            send(label, local);
            this.count = count + 1;
        }
    }
    """

    private func reads(knownProperties: Set<String>) throws -> [FieldAccess] {
        let fixture = try #require(JavaFixture(source))
        let body = try #require(fixture.methodBody("run"))
        return FieldReadResolver(context: fixture.context, identifierTypes: ["identifier"])
            .reads(in: body, knownProperties: knownProperties)
    }

    @Test("Every identifier matching a known property name is recorded, with its own location")
    func knownPropertyNamesAreRecorded() throws {
        let reads = try reads(knownProperties: ["count", "label"])
        #expect(reads.map(\.name) == ["count", "label", "count", "count"])
        #expect(reads.compactMap { $0.location?.line } == [3, 4, 5, 5])
        // Bare and `this.`-qualified reads alike are recorded without a receiver, as the engine
        // filters by name only.
        #expect(reads.allSatisfy { $0.receiver == nil })
    }

    @Test("Identifiers that name no known property are ignored")
    func unknownIdentifiersAreIgnored() throws {
        #expect(try reads(knownProperties: ["count"]).map(\.name) == ["count", "count", "count"])
        #expect(try reads(knownProperties: ["nothing"]).isEmpty)
    }

    @Test("With no known properties the walk is skipped entirely")
    func noKnownPropertiesYieldsNothing() throws {
        #expect(try reads(knownProperties: []).isEmpty)
    }

    @Test("A node type the grammar does not use for identifiers captures nothing")
    func onlyTheListedIdentifierTypesAreRead() throws {
        let fixture = try #require(JavaFixture(source))
        let body = try #require(fixture.methodBody("run"))
        let resolver = FieldReadResolver(context: fixture.context, identifierTypes: ["simple_identifier"])
        #expect(resolver.reads(in: body, knownProperties: ["count"]).isEmpty)
    }

    @Test("A scope supplies the full property-name set, untyped properties included")
    func scopeOverloadUsesEveryPropertyName() throws {
        let fixture = try #require(JavaFixture(source))
        let body = try #require(fixture.methodBody("run"))
        let scope = CallSiteScope(
            knownProperties: ["count": "int"], knownPropertyNames: ["count", "label"])
        let resolver = FieldReadResolver(context: fixture.context, identifierTypes: ["identifier"])
        #expect(resolver.reads(in: body, scope: scope).map(\.name) == ["count", "label", "count", "count"])
        #expect(resolver.reads(in: nil, scope: scope).isEmpty)
    }
}
