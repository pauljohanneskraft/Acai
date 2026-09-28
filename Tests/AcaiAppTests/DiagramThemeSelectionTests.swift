import Foundation
import SwiftUI
import Testing
@testable import AcaiApp

@Suite("Diagram theme selection")
struct DiagramThemeSelectionTests {
    private func fixtureStore(_ path: String) -> DiagramThemeStore {
        DiagramThemeStore(fixtureBaseDir: URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("seeded", isDirectory: true))
    }

    private func withCleanup<T>(_ stores: [DiagramThemeStore], _ body: () throws -> T) rethrows -> T {
        defer {
            for suite in stores.compactMap(\.suiteName) {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        }
        return try body()
    }

    @Test("Without a UI-test fixture the theme lives in the user's standard defaults")
    func realUserUsesStandardDefaults() {
        let store = DiagramThemeStore(fixtureBaseDir: nil)

        #expect(store.suiteName == nil)
        #expect(store.defaults === UserDefaults.standard)
    }

    @Test("Two staging directories with the same last path component get independent stores")
    func differentBaseDirsAreIndependent() {
        let first = fixtureStore("/private/tmp/AcaiUITestFixtures/iOS/FirstJourney.testA")
        let second = fixtureStore("/private/tmp/AcaiUITestFixtures/iOS/SecondJourney.testB")
        withCleanup([first, second]) {
            #expect(first.suiteName != second.suiteName)

            first.defaults.set(DiagramThemeSelection.dark.rawValue, forKey: DiagramThemeSelection.storageKey)

            #expect(first.selection == .dark)
            #expect(second.selection == .system)
        }
    }

    @Test("The same staging directory names the same store, however its path is spelled")
    func sameBaseDirIsStable() {
        let path = "/private/tmp/AcaiUITestFixtures/iOS/Journey.test/seeded"
        let plain = DiagramThemeStore(fixtureBaseDir: URL(fileURLWithPath: path))
        let dotted = DiagramThemeStore(fixtureBaseDir: URL(fileURLWithPath: path + "/../seeded"))

        #expect(plain.suiteName == dotted.suiteName)
        #expect(plain.suiteName?.contains("/") == false)
    }

    @Test("A saved theme persists into a fresh read of the store")
    func selectionPersists() {
        let baseDir = URL(fileURLWithPath: "/private/tmp/AcaiThemeTests/\(UUID().uuidString)/seeded")
        let store = DiagramThemeStore(fixtureBaseDir: baseDir)
        withCleanup([store]) {
            #expect(store.selection == .system)

            store.defaults.set(DiagramThemeSelection.light.rawValue, forKey: DiagramThemeSelection.storageKey)

            #expect(DiagramThemeStore(fixtureBaseDir: baseDir).selection == .light)
        }
    }

    @Test("An unrecognised stored value falls back to following the system")
    func unknownValueFallsBackToSystem() {
        let store = fixtureStore("/private/tmp/AcaiThemeTests")
        withCleanup([store]) {
            store.defaults.set("sepia", forKey: DiagramThemeSelection.storageKey)

            #expect(store.selection == .system)
        }
    }

    @Test("A pick in the View menu reaches the settings picker and the export path")
    @MainActor
    func viewMenuPickSyncsEverywhere() {
        let store = fixtureStore("/private/tmp/AcaiThemeTests")
        withCleanup([store]) {
            let viewMenu = AppStorage(
                wrappedValue: DiagramThemeSelection.system, DiagramThemeSelection.storageKey, store: store.defaults)
            let settingsPicker = AppStorage(
                wrappedValue: DiagramThemeSelection.system, DiagramThemeSelection.storageKey, store: store.defaults)

            viewMenu.wrappedValue = .dark

            #expect(settingsPicker.wrappedValue == .dark)
            #expect(store.selection == .dark)
            #expect(store.selection.exportTheme != nil)
        }
    }

    @Test("Only an explicit light or dark pick bakes colours into an export")
    func exportThemePerSelection() {
        #expect(DiagramThemeSelection.system.exportTheme == nil)
        #expect(DiagramThemeSelection.light.exportTheme != nil)
        #expect(DiagramThemeSelection.dark.exportTheme != nil)
    }
}
