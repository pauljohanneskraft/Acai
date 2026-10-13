import Testing

@testable import AcaiCore

@Suite("Module Resolution")
struct ModuleResolverTests {

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

    // MARK: - Qualified by project root

    private func product(_ path: String, inRoot root: String) -> String {
        ModuleResolver.standard.productName(forFilePath: path, inRoot: root)
    }

    @Test func rootQualifiesTheAnchorDerivedName() {
        #expect(product("app-ios/Sources/Networking/Client.swift", inRoot: "app-ios") == "app-ios/Networking")
        #expect(product("web/packages/core/src/index.ts", inRoot: "web") == "web/core")
        #expect(product("jvm/feature/login/src/main/java/L.java", inRoot: "jvm") == "jvm/login")
    }

    @Test func sameNamedTargetsInTwoRootsStayDistinct() {
        #expect(product("app-ios/Sources/Core/A.swift", inRoot: "app-ios") == "app-ios/Core")
        #expect(product("app-mac/Sources/Core/A.swift", inRoot: "app-mac") == "app-mac/Core")
    }

    /// A single-module project — `src` at the root's head, or no anchor at all — is the root itself,
    /// rather than inventing a module from the leading directory.
    @Test func aRootWithoutAnAnchorIsTheRootItself() {
        #expect(product("web/src/app.ts", inRoot: "web") == "web")
        #expect(product("proxy/app.py", inRoot: "proxy") == "proxy")
        #expect(product("lib/main.dart", inRoot: "lib") == "lib")
    }

    @Test func theAnalysedFolderItselfIsNamedByTheFallbackGroup() {
        #expect(product("Sources/AcaiCore/Foo.swift", inRoot: ".") == "\(fallback)/AcaiCore")
        #expect(product("Foo.swift", inRoot: ".") == fallback)
    }

    @Test func aNestedRootIsStrippedWhole() {
        #expect(product("apps/web/packages/ui/Button.tsx", inRoot: "apps/web") == "web/ui")
    }

    /// A path that does not sit under the root it was handed is scanned whole rather than silently
    /// mis-stripped.
    @Test func aPathOutsideItsRootKeepsTheRootsName() {
        #expect(product("other/Sources/Core/A.swift", inRoot: "web") == "web/Core")
    }
}
