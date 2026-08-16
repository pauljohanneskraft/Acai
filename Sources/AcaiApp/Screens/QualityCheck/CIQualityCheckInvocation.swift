import Foundation

/// Formats the `acai quality` invocation for a codebase's already-configured quality-rules file —
/// backing the "Export CI Check" action next to `QualityCheckSection`.
struct CIQualityCheckInvocation {
    let directoryPath: String
    let rulesPath: String

    /// `rulesPath` relative to `directoryPath`, when the rules file lives inside the codebase's own
    /// folder. `nil` when it lives elsewhere (an app-managed or externally pointed-at file) — such a
    /// path won't exist on a CI runner's checkout, so `ciRulesPath` falls back to a placeholder.
    private var relativeRulesPath: String? {
        let directory = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
        let rules = URL(fileURLWithPath: rulesPath).standardizedFileURL.path
        guard rules.hasPrefix(directory + "/") else { return nil }
        return String(rules.dropFirst(directory.count + 1))
    }

    /// Whether the sheet should show its "commit your rules file first" note.
    var needsExportNote: Bool {
        relativeRulesPath == nil
    }

    private var ciRulesPath: String {
        relativeRulesPath ?? "quality.yml"
    }

    var shellCommand: String {
        "acai quality --source \(directoryPath.shellQuoted) --rules \(rulesPath.shellQuoted)"
    }

    var gitHubActionsStep: String {
        guard needsExportNote else {
            return """
            - name: Acai quality check
              run: acai quality --source . --rules \(ciRulesPath.shellQuoted)
            """
        }
        return """
        - name: Acai quality check
          # This codebase's rules file isn't inside its own folder, so a CI checkout won't have
          # it — commit a copy into the repository (e.g. at the path below) before using this step.
          run: acai quality --source . --rules \(ciRulesPath.shellQuoted)
        """
    }
}

private extension String {
    /// Sized for the paths this formats — not a general shell-argument parser.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
