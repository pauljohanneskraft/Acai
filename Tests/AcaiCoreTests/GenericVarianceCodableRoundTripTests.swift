import Testing
import Foundation
@testable import AcaiCore

@Suite("Generic Variance Codable Round Trip Tests")
struct GenericVarianceCodableRoundTripTests {

    @Test func genericParameterVariance() throws {
        for variance in [Variance.covariant, .contravariant, .invariant] {
            let original = GenericParameter(
                name: "T",
                constraints: [GenericConstraint(kind: .conformance, type: TypeReference(name: "Comparable"))],
                variance: variance
            )
            #expect(try roundTrip(original) == original)
        }
    }

    /// A parameter written before variance existed carries no key, and reads back as "none declared"
    /// rather than failing to decode.
    @Test func genericParameterWithoutVarianceDecodesAsNil() throws {
        let json = Data(#"{"name":"T","constraints":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(GenericParameter.self, from: json)
        #expect(decoded.name == "T")
        #expect(decoded.variance == nil)
    }

    /// The key is omitted rather than written as `null`, so an artifact from a language with no
    /// variance is byte-identical to one encoded before the field existed.
    @Test func absentVarianceIsNotEncoded() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(GenericParameter(name: "T"))
        let encoded = try #require(String(bytes: data, encoding: .utf8))
        #expect(!encoded.contains("variance"))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
