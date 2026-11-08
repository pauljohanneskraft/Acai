import AcaiCore
import Testing
@testable import AcaiTreeSitter

@Suite("Modifier Classifier")
struct ModifierClassifierTests {

    /// A Java-shaped classifier: package-private by default, annotations collected verbatim, and one
    /// `postProcess` rule that depends on the assembled result rather than a single child.
    private let classifier = ModifierClassifier(
        defaultAccessLevel: .packagePrivate,
        annotationNodeTypes: ["annotation", "marker_annotation"],
        classify: { nodeType, _ in
            switch nodeType {
            case "public": .accessLevel(.public)
            case "protected": .accessLevel(.protected)
            case "private": .accessLevel(.private)
            case "static": .modifier(.static)
            case "final": .modifier(.final)
            case "abstract": .modifier(.abstract)
            default: nil
            }
        },
        postProcess: { info in
            if info.annotations.contains("@Override"), !info.modifiers.contains(.override) {
                info.modifiers.append(.override)
            }
        })

    private func modifierInfo(of source: String) throws -> ModifierInfo {
        let fixture = try #require(JavaFixture(source))
        return classifier.modifierInfo(for: fixture.firstNode(ofType: "modifiers"), in: fixture.context)
    }

    @Test("Access level, modifiers and annotations are split out of one `modifiers` node")
    func modifiersNodeIsSplitByClassification() throws {
        let info = try modifierInfo(of: """
        class A {
            @SuppressWarnings("unchecked")
            private static final int x = 1;
        }
        """)
        #expect(info.accessLevel == .private)
        #expect(info.modifiers == [.static, .final])
        #expect(info.annotations == ["@SuppressWarnings(\"unchecked\")"])
    }

    @Test("A marker annotation is normalised with a leading `@` and can drive a post-process rule")
    func postProcessSeesTheAssembledResult() throws {
        let info = try modifierInfo(of: """
        class A {
            @Override
            public void run() {}
        }
        """)
        #expect(info.accessLevel == .public)
        #expect(info.annotations == ["@Override"])
        #expect(info.modifiers == [.override])
    }

    @Test("A declaration with no `modifiers` node takes the language's implicit visibility")
    func absentModifiersNodeYieldsTheDefault() {
        let info = classifier.modifierInfo(
            for: nil, in: SourceFileContext(source: "", fileName: "Fixture.java"))
        #expect(info == ModifierInfo(accessLevel: .packagePrivate))
    }

    @Test("Children the classifier does not recognise are skipped rather than collected")
    func unclassifiedChildrenAreSkipped() throws {
        let info = try modifierInfo(of: """
        class A {
            synchronized native void run();
        }
        """)
        #expect(info.accessLevel == .packagePrivate)
        #expect(info.modifiers.isEmpty)
        #expect(info.annotations.isEmpty)
    }
}
