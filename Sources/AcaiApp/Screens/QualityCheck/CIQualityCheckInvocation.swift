import Foundation

/// Formats the `acai quality` invocation for a codebase's already-configured quality-rules file —
/// backing the "Export CI Check" action next to `QualityCheckSection`. Purely a string formatter
/// over data the app already persists (`Codebase.directoryPath` and the codebase's
/// `QualityCheckConfiguration.rulesPath`); it adds no new engine capability, and it is only ever
/// constructed once a rules file is actually configured (see `QualityCheckSection.configuration`).
struct CIQualityCheckInvocation {
    /// The codebase's on-disk directory — becomes the local shell command's `--source`.
    let directoryPath: String
    /// The configured rules file's real, current path (never a placeholder).
    let rulesPath: String

    /// The rules path expressed relative to `directoryPath`, when the rules file actually lives
    /// inside the codebase's own folder (the common case: a `quality.yml` committed alongside the
    /// source it checks). `nil` when the file lives elsewhere on disk — an app-managed rules file
    /// (authored in the in-app editor, stored in the app's own sandbox) or an external file the
    /// user pointed at outside the repository. Neither exists on a CI runner's checkout, so there
    /// is no path to give CI in that case — `ciRulesPath` falls back to a placeholder instead.
    private var relativeRulesPath: String? {
        let directory = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
        let rules = URL(fileURLWithPath: rulesPath).standardizedFileURL.path
        guard rules.hasPrefix(directory + "/") else { return nil }
        return String(rules.dropFirst(directory.count + 1))
    }

    /// Whether `rulesPath` is unreachable from a CI checkout, so the exported snippet had to fall
    /// back to a placeholder filename instead of the real configured path — the sheet uses this to
    /// show its "commit your rules file first" note.
    var needsExportNote: Bool {
        relativeRulesPath == nil
    }

    /// The rules-file path to reference from a GitHub Actions checkout: the real path relative to
    /// the codebase's directory when possible, otherwise a conventional placeholder name that the
    /// generated step's own comment calls out as needing to be committed first.
    private var ciRulesPath: String {
        relativeRulesPath ?? "quality.yml"
    }

    /// Runnable as-is, from any working directory, against the codebase's real configured rules
    /// file — this is what makes the "correct, real rules path" claim: both arguments are the
    /// literal, currently-configured paths, not a computed guess.
    var shellCommand: String {
        "acai quality --source \(directoryPath.shellQuoted) --rules \(rulesPath.shellQuoted)"
    }

    /// A ready-to-paste step for a `.github/workflows/*.yml` job that already checks out the repo.
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
    /// Single-quotes `self` for safe interpolation into a POSIX shell command, escaping any
    /// embedded single quote the standard `'\''` way. Sized for the paths this formats — not a
    /// general shell-argument parser.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
