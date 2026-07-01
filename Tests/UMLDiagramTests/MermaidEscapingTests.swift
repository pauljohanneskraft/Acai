import Testing
@testable import UMLDiagram

/// Unit tests for the Mermaid escaping/id helpers (`MermaidEscaping.swift`). These string rules are
/// what keep special characters in type names, generics, and labels from breaking a generated
/// Mermaid diagram, and were previously only exercised indirectly through the renderer goldens.
@Suite("Mermaid escaping")
struct MermaidEscapingTests {

    @Test func safeIDReplacesNonAlphanumericsAndLeadingDigits() {
        #expect("A.B".mermaidSafeID == "A_B")
        #expect("A-B".mermaidSafeID == "A_B")
        #expect("com.example.Foo".mermaidSafeID == "com_example_Foo")
        // A leading digit is prefixed with `_` (Mermaid ids may not start with a number).
        #expect("3Tier".mermaidSafeID == "_3Tier")
        #expect("".mermaidSafeID == "_")
    }

    @Test func idAllocatorDisambiguatesCollisions() {
        var allocator = MermaidIDAllocator()
        // `A.B` and `A-B` both reduce to `A_B`; the allocator must keep them distinct.
        #expect(allocator.id(for: "A.B") == "A_B")
        #expect(allocator.id(for: "A-B") == "A_B_2")
        #expect(allocator.id(for: "A/B") == "A_B_3")
    }

    @Test func labelEscapingHandlesQuotesAndNewlines() {
        #expect("say \"hi\"".mermaidLabelEscaped == "say #quot;hi#quot;")
        #expect("line1\nline2".mermaidLabelEscaped == "line1<br/>line2")
    }

    @Test func textEscapingHandlesColonsAndNewlines() {
        #expect("a:b".mermaidTextEscaped == "a#colon;b")
        #expect("a\nb".mermaidTextEscaped == "a b")
    }

    @Test func genericsUseTildeNotation() {
        #expect("List<Item>".mermaidGenerics == "List~Item~")
        #expect("Dictionary<String, Foo>".mermaidGenerics == "Dictionary~String, Foo~")
    }
}
