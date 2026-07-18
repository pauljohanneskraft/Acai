import Testing

@testable import AcaiCore

@Suite("Module Resolution")
struct ModuleResolverTests {

    /// The standard resolver's product name for a path.
    private func product(_ path: String) -> String {
        ModuleResolver.standard.productName(forFilePath: path)
    }

    private var fallback: String { ModuleResolver.standard.fallbackGroup }

    @Test func swiftPackageManagerTarget() {
        #expect(product("Sources/AcaiCore/CodeArtifact.swift") == "AcaiCore")
        #expect(product("Sources/AcaiDiagram/ClassDiagram/ClassDiagramDOTRenderer.swift") == "AcaiDiagram")
    }

    @Test func swiftPackageManagerTestTarget() {
        #expect(product("Tests/AcaiCoreTests/ModuleResolverTests.swift") == "AcaiCoreTests")
    }

    @Test func gradleMavenModule() {
        #expect(product("app/src/main/kotlin/com/example/Main.kt") == "app")
        #expect(product("feature/login/src/main/java/com/example/Login.java") == "login")
        #expect(product("core/src/test/kotlin/CoreTest.kt") == "core")
    }

    @Test func singleModuleSrcAtRoot() {
        // `src` with no module prefix collapses to the single fallback group.
        #expect(product("src/main/java/App.java") == fallback)
    }

    @Test func jsTypeScriptMonorepo() {
        #expect(product("packages/core/src/index.ts") == "core")
        #expect(product("packages/ui/components/Button.tsx") == "ui")
    }

    @Test func flutterAndTopLevelFallback() {
        // No marker → first directory component.
        #expect(product("lib/main.dart") == "lib")
        #expect(product("MyApp/Models/User.swift") == "MyApp")
    }

    @Test func fileAtRootCollapses() {
        #expect(product("Foo.swift") == fallback)
    }

    @Test func leadingSlashAndDotAreIgnored() {
        #expect(product("/Sources/AcaiCore/Foo.swift") == "AcaiCore")
        #expect(product("./Sources/AcaiCore/Foo.swift") == "AcaiCore")
    }
}
