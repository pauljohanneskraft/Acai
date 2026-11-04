import AppIntents

/// The actions Siri, Spotlight and the Shortcuts app offer without the user assembling a shortcut
/// first. Both app targets pull this in through `AcaiAppIntentsPackage`, so one provider serves
/// macOS and iOS.
///
/// A phrase is keyed by its own English text rather than by an identifier, in the app targets'
/// `AppShortcuts.xcstrings`: the system reads the phrase list out of the built metadata, where
/// `\(.applicationName)` becomes `${applicationName}`. The short titles stay identifiers in
/// `AppIntents.xcstrings` beside the intent titles they shorten.
struct AcaiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReindexCodebaseIntent(),
            phrases: [
                "Reindex a codebase in \(.applicationName)",
                "Reindex my \(.applicationName) codebase",
                "Analyze a codebase in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcut.ReindexCodebase.ShortTitle", table: "AppIntents"),
            systemImageName: "arrow.clockwise"
        )

        AppShortcut(
            intent: GetCodebaseMetricsIntent(),
            phrases: [
                "Get \(.applicationName) metrics",
                "Get codebase metrics in \(.applicationName)",
                "How big is my \(.applicationName) codebase"
            ],
            shortTitle: LocalizedStringResource("Shortcut.GetCodebaseMetrics.ShortTitle", table: "AppIntents"),
            systemImageName: "chart.xyaxis.line"
        )

        AppShortcut(
            intent: RunQualityCheckIntent(),
            phrases: [
                "Check the quality of my \(.applicationName) codebase",
                "\(.applicationName) quality check",
                "Is my \(.applicationName) codebase healthy"
            ],
            shortTitle: LocalizedStringResource("Shortcut.RunQualityCheck.ShortTitle", table: "AppIntents"),
            systemImageName: "checkmark.seal"
        )

        AppShortcut(
            intent: GetDependentsIntent(),
            phrases: [
                "Get dependents in \(.applicationName)",
                "What depends on a type in \(.applicationName)",
                "Get \(.applicationName) dependents of a type"
            ],
            shortTitle: LocalizedStringResource("Shortcut.GetDependents.ShortTitle", table: "AppIntents"),
            systemImageName: "point.3.connected.trianglepath.dotted"
        )
    }
}
