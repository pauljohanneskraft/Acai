import Testing
import AcaiArtifactGenerator
import AcaiCore
@testable import AcaiDiagram

/// A node identifier is derived from a type name, and a type name is whatever the source said — so
/// unicode, spaces, punctuation, a leading digit, a language keyword and the empty string all have to
/// yield a usable, unique identifier. Checked across the whole hostile name alphabet rather than a
/// few hand-picked names.
@Suite("Diagram identifier invariants", .timeLimit(.minutes(1)))
struct DiagramIdentifierInvariantTests {
    private let names = TypeNameAlphabet.standard.names

    @Test("Every Mermaid id is a valid identifier")
    func everyMermaidIDIsAValidIdentifier() {
        for name in names {
            let identifier = name.mermaidSafeID
            #expect(!identifier.isEmpty, "empty id for \(String(reflecting: name))")
            #expect(
                identifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                "id \(String(reflecting: identifier)) for \(String(reflecting: name)) is not alphanumeric/underscore"
            )
            #expect(
                identifier.first?.isNumber == false,
                "id \(String(reflecting: identifier)) for \(String(reflecting: name)) starts with a digit"
            )
        }
    }

    @Test("The Mermaid allocator never hands the same id to two names")
    func theMermaidAllocatorNeverCollides() {
        var allocator = MermaidIDAllocator()
        var seen: [String: String] = [:]
        for name in names {
            let identifier = allocator.id(for: name)
            let previous = String(reflecting: seen[identifier] ?? "")
            #expect(
                seen[identifier] == nil,
                "id \(String(reflecting: identifier)) reused for \(String(reflecting: name)) and \(previous)"
            )
            #expect(
                identifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                "disambiguated id \(String(reflecting: identifier)) is not a valid identifier"
            )
            seen[identifier] = name
        }
    }

    /// The same allocator, driven by the generated artifacts rather than the alphabet directly, so the
    /// repetition pattern a real diagram produces is covered too.
    @Test("Allocation over a generated artifact's types stays unique")
    func allocationOverGeneratedArtifactsStaysUnique() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = ArtifactGenerator(seed: seed).makeArtifact()
            var allocator = MermaidIDAllocator()
            var seen: Set<String> = []
            for type in artifact.flattened() {
                let identifier = allocator.id(for: type.id)
                #expect(seen.insert(identifier).inserted, "id \(identifier) reused for seed \(seed)")
            }
        }
    }

    @Test("A DOT node id is a single balanced quoted string")
    func aDOTNodeIDIsASingleBalancedQuotedString() {
        for name in names {
            let identifier = name.dotNodeID
            #expect(identifier.hasPrefix("\"") && identifier.hasSuffix("\""), "\(String(reflecting: name))")
            #expect(identifier.count >= 2, "\(String(reflecting: name))")

            // Every quote inside the body must be backslash-escaped, or the id ends early and the
            // rest of the name leaks into the DOT grammar as attributes.
            let body = Array(identifier.dropFirst().dropLast())
            var index = 0
            while index < body.count {
                if body[index] == "\\" {
                    index += 2
                    continue
                }
                #expect(body[index] != "\"", "unescaped quote in DOT id for \(String(reflecting: name))")
                index += 1
            }
        }
    }

    @Test("Distinct type ids stay distinct as DOT node ids")
    func distinctTypeIDsStayDistinctAsDOTNodeIDs() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let identifiers = ArtifactGenerator(seed: seed).makeArtifact().flattened().map(\.id)
            #expect(
                Set(identifiers.map(\.dotNodeID)).count == Set(identifiers).count,
                "two distinct type ids collapsed to one DOT node id for seed \(seed)"
            )
        }
    }
}
