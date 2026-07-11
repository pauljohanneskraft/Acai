import Testing
@testable import UMLJVM
@testable import UMLCore

@Suite("Java: Modifier Tests")
struct JavaModifierTests {
    let parser = JavaCodeParser()

    @Test func modifiersAbstract() {
        let source = """
        public abstract class AbstractBase {
            public abstract void abstractMethod();
            public void concreteMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "AbstractBase.java")
        let base = artifact.types[0]
        #expect(base.modifiers.contains(.abstract) == true)

        let abstractMethod = base.members.first { $0.name == "abstractMethod" }
        #expect(abstractMethod?.modifiers.contains(.abstract) == true)

        let concreteMethod = base.members.first { $0.name == "concreteMethod" }
        #expect(concreteMethod?.modifiers.contains(.abstract) == false)
    }

    /// `@Override` maps to the `.override` modifier so the dead-code scan exempts the override (RC3).
    @Test func annotationOverrideMapsToModifier() {
        let source = """
        class Impl extends Base {
            @Override
            protected void hook() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Impl.java")
        let hook = artifact.types[0].members.first { $0.name == "hook" }
        #expect(hook?.modifiers.contains(.override) == true)
    }

    @Test func modifiersStatic() {
        let source = """
        public class Utils {
            public static String CONSTANT = "value";
            public static void staticMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Utils.java")
        let utils = artifact.types[0]

        let constant = utils.members.first { $0.name == "CONSTANT" }
        #expect(constant?.modifiers.contains(.static) == true)

        let method = utils.members.first { $0.name == "staticMethod" }
        #expect(method?.modifiers.contains(.static) == true)
    }

    @Test func modifiersFinal() {
        let source = """
        public final class Immutable {
            private final String value;
            public final void finalMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Immutable.java")
        let immutable = artifact.types[0]
        #expect(immutable.modifiers.contains(.final) == true)

        let field = immutable.members.first { $0.name == "value" }
        #expect(field?.modifiers.contains(.final) == true)

        let method = immutable.members.first { $0.name == "finalMethod" }
        #expect(method?.modifiers.contains(.final) == true)
    }

    @Test func modifiersSynchronized() {
        let source = """
        public class ThreadSafe {
            public synchronized void syncMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "ThreadSafe.java")
        let threadSafe = artifact.types[0]
        let method = threadSafe.members.first { $0.name == "syncMethod" }
        #expect(method?.modifiers.contains(.synchronized) == true)
    }

    @Test func modifiersVolatile() {
        let source = """
        public class Concurrent {
            private volatile boolean flag;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Concurrent.java")
        let concurrent = artifact.types[0]
        let field = concurrent.members.first { $0.name == "flag" }
        #expect(field?.modifiers.contains(.volatile) == true)
    }

    @Test func modifiersTransient() {
        let source = """
        public class Serialization {
            private transient String tempData;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Serialization.java")
        let serialization = artifact.types[0]
        let field = serialization.members.first { $0.name == "tempData" }
        #expect(field?.modifiers.contains(.transient) == true)
    }

    @Test func modifiersNative() {
        let source = """
        public class NativeLib {
            public native void nativeMethod();
        }
        """
        let artifact = parser.parse(source: source, fileName: "NativeLib.java")
        let nativeLib = artifact.types[0]
        let method = nativeLib.members.first { $0.name == "nativeMethod" }
        #expect(method?.modifiers.contains(.native) == true)
    }

    @Test func modifiersStrictfp() {
        let source = """
        public strictfp class StrictFloatingPoint {
            public strictfp void strictMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "StrictFloatingPoint.java")
        let strictClass = artifact.types[0]
        #expect(strictClass.modifiers.contains(.strictfp) == true)

        let method = strictClass.members.first { $0.name == "strictMethod" }
        #expect(method?.modifiers.contains(.strictfp) == true)
    }

    @Test func modifiersDefault() {
        let source = """
        public interface DefaultMethods {
            default void defaultMethod() {
                System.out.println("default");
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "DefaultMethods.java")
        let iface = artifact.types[0]
        let method = iface.members.first { $0.name == "defaultMethod" }
        #expect(method?.modifiers.contains(.default) == true)
    }

}
