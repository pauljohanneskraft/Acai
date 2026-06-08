import Testing

@testable import UMLCore

@Suite("Build Product Resolution")
struct BuildProductTests {

    @Test func swiftPackageManagerTarget() {
        #expect(BuildProduct.productName(forFilePath: "Sources/UMLCore/CodeArtifact.swift") == "UMLCore")
        #expect(
            BuildProduct.productName(forFilePath: "Sources/UMLDiagram/ClassDiagram/DOTGenerator.swift") == "UMLDiagram")
    }

    @Test func swiftPackageManagerTestTarget() {
        #expect(BuildProduct.productName(forFilePath: "Tests/UMLCoreTests/BuildProductTests.swift") == "UMLCoreTests")
    }

    @Test func gradleMavenModule() {
        #expect(BuildProduct.productName(forFilePath: "app/src/main/kotlin/com/example/Main.kt") == "app")
        #expect(BuildProduct.productName(forFilePath: "feature/login/src/main/java/com/example/Login.java") == "login")
        #expect(BuildProduct.productName(forFilePath: "core/src/test/kotlin/CoreTest.kt") == "core")
    }

    @Test func singleModuleSrcAtRoot() {
        // `src` with no module prefix collapses to the single fallback group.
        #expect(BuildProduct.productName(forFilePath: "src/main/java/App.java") == BuildProduct.fallbackGroup)
    }

    @Test func jsTypeScriptMonorepo() {
        #expect(BuildProduct.productName(forFilePath: "packages/core/src/index.ts") == "core")
        #expect(BuildProduct.productName(forFilePath: "packages/ui/components/Button.tsx") == "ui")
    }

    @Test func flutterAndTopLevelFallback() {
        // No marker → first directory component.
        #expect(BuildProduct.productName(forFilePath: "lib/main.dart") == "lib")
        #expect(BuildProduct.productName(forFilePath: "MyApp/Models/User.swift") == "MyApp")
    }

    @Test func fileAtRootCollapses() {
        #expect(BuildProduct.productName(forFilePath: "Foo.swift") == BuildProduct.fallbackGroup)
    }

    @Test func leadingSlashAndDotAreIgnored() {
        #expect(BuildProduct.productName(forFilePath: "/Sources/UMLCore/Foo.swift") == "UMLCore")
        #expect(BuildProduct.productName(forFilePath: "./Sources/UMLCore/Foo.swift") == "UMLCore")
    }
}
