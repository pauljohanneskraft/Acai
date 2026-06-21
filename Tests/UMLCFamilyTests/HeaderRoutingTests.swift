import Testing
@testable import UMLCFamily
@testable import UMLCore

/// `.h` is owned by `CCodeParser`, which content-sniffs each header and parses it with the matching
/// grammar+extractor, reporting the dialect it actually is.
@Suite("C-family: .h header routing")
struct HeaderRoutingTests {
    let parser = CCodeParser()

    @Test func plainCHeaderReportsC() {
        let source = """
        struct Vec3 {
            float x;
            float y;
            float z;
        };

        void normalize(struct Vec3 *v);
        """
        let artifact = parser.parse(source: source, fileName: "vec3.h")
        #expect(artifact.metadata.sourceLanguage == .c)
        #expect(artifact.types.first?.name == "Vec3")
    }

    @Test func cppHeaderIsRoutedToCpp() {
        let source = """
        namespace geometry {
            class Vector3 {
            public:
                float length() const;
            private:
                float x_, y_, z_;
            };
        }
        """
        let artifact = parser.parse(source: source, fileName: "vector3.h")
        #expect(artifact.metadata.sourceLanguage == .cpp)
        let vector = artifact.types.first { $0.name == "Vector3" }
        #expect(vector?.kind == .class)
        #expect(vector?.namespace == "geometry")
    }

    @Test func commentMentioningClassStaysC() {
        // "class" appears only in a comment and a string — must not trip the C++ classifier.
        let source = """
        /* This models a widget class for the UI. */
        struct Widget {
            int id;
        };
        const char *label = "the class label";
        """
        let artifact = parser.parse(source: source, fileName: "widget.h")
        #expect(artifact.metadata.sourceLanguage == .c)
    }

    @Test func classifierDetectsScopeResolution() {
        #expect(CFamilyHeaderClassifier(source: "int n = std::max(1, 2);").looksLikeCpp)
        #expect(!CFamilyHeaderClassifier(source: "int n = max(1, 2);").looksLikeCpp)
    }
}
