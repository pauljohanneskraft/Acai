import Testing
@testable import UMLDiagram

@Suite("Mermaid ID Allocator")
struct MermaidIDAllocatorTests {

    @Test func distinctSourcesCollidingUnderSafeIDGetUniqueIDs() {
        var allocator = MermaidIDAllocator()
        // Both map to "A_B" under mermaidSafeID; they must not collapse to one node.
        let first = allocator.id(for: "A.B")
        let second = allocator.id(for: "A-B")
        #expect(first == "A_B")
        #expect(second == "A_B_2")
        #expect(first != second)
    }

    @Test func suffixedIDDoesNotCollideWithALaterBase() {
        var allocator = MermaidIDAllocator()
        #expect(allocator.id(for: "A.B") == "A_B")        // base
        #expect(allocator.id(for: "A-B") == "A_B_2")      // disambiguated
        #expect(allocator.id(for: "A_B_2") == "A_B_2_2")  // would have collided with the suffixed id
    }

    @Test func uniqueSourcesKeepReadableIDs() {
        var allocator = MermaidIDAllocator()
        #expect(allocator.id(for: "Foo") == "Foo")
        #expect(allocator.id(for: "Bar") == "Bar")
    }
}
