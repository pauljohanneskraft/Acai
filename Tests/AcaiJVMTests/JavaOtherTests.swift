import Testing
@testable import AcaiJVM
@testable import AcaiCore

@Suite("Java: Other Tests")
struct JavaOtherTests {
    let parser = JavaCodeParser()

    @Test func annotationType() {
        let source = """
        public @interface CustomAnnotation {
            String value();
            int priority() default 0;
        }
        """
        let artifact = parser.parse(source: source, fileName: "CustomAnnotation.java")
        #expect(artifact.types.count == 1)
        let annotation = artifact.types[0]
        #expect(annotation.kind == .annotation)
        #expect(annotation.members.count >= 1)
    }

    @Test func accessLevels() {
        let source = """
        public class AccessLevels {
            public String publicField;
            private String privateField;
            protected String protectedField;
            String packagePrivateField;
        }
        """
        let artifact = parser.parse(source: source, fileName: "AccessLevels.java")
        let accessLevels = artifact.types[0]

        let publicField = accessLevels.members.first { $0.name == "publicField" }
        #expect(publicField?.accessLevel == .public)

        let privateField = accessLevels.members.first { $0.name == "privateField" }
        #expect(privateField?.accessLevel == .private)

        let protectedField = accessLevels.members.first { $0.name == "protectedField" }
        #expect(protectedField?.accessLevel == .protected)

        let packagePrivate = accessLevels.members.first { $0.name == "packagePrivateField" }
        #expect(packagePrivate?.accessLevel == nil || packagePrivate?.accessLevel == .packagePrivate)
    }

}
