import Foundation
import AcaiQuality

/// A per-codebase, ordered file allow/blocklist evaluated against each file's path relative to the
/// codebase root, applied at indexing time (`CodebaseAnalyzer`) so an excluded file is never even
/// parsed. `nil` on `Codebase.fileFilter` — and an empty `rules` list — both mean "no filtering,"
/// identical to every codebase's behavior before this existed.
///
/// See `USABILITY_IMPROVEMENTS.md` Part 12, "File-level allow/blocklist."
struct FileFilter: Codable, Hashable, Sendable {
    var rules: [Rule] = []

    /// Whether `relativePath` should be parsed, evaluating `rules` in order and taking the *last*
    /// match — `.gitignore`-style, so a later, more specific rule can override an earlier general
    /// one. No matching rule (including an empty rule list) means "include," so a freshly added
    /// codebase with no filter configured behaves exactly as before this existed.
    ///
    /// To scope a codebase down to only a subset ("only analyze `Sources/Core/**`"), block
    /// everything first (`.block("*")`) then allow the subset — the same two-rule idiom
    /// `.gitignore` negation uses, rather than a second, implicit "any allow rule flips the
    /// default" mode that would make a mixed allow+block list ambiguous.
    func includes(_ relativePath: String) -> Bool {
        var result = true
        for rule in rules where rule.matches(relativePath) {
            result = rule.action == .allow
        }
        return result
    }
}

extension FileFilter {
    struct Rule: Codable, Hashable, Sendable, Identifiable {
        var id: UUID = UUID()
        var pattern: String
        var syntax: Syntax
        var action: Action

        enum Syntax: String, Codable, Hashable, Sendable, CaseIterable {
            case glob
            case regex
        }

        enum Action: String, Codable, Hashable, Sendable, CaseIterable {
            case allow
            case block
        }

        init(pattern: String, syntax: Syntax, action: Action) {
            self.pattern = pattern
            self.syntax = syntax
            self.action = action
        }

        /// A ceiling on the path length a regex rule is evaluated against. Real file paths are a
        /// few hundred characters at most; bounding the input size forecloses the worst
        /// catastrophic-backtracking blowups tied to input length — user-supplied regex against a
        /// large file tree is exactly the risk `USABILITY_GUARDRAILS.md` §5 calls out. This isn't
        /// a full guarantee (a pathological pattern can still be slow on a short string), but it
        /// removes the "attacker controls both pattern and a huge input" half of the risk, since
        /// the input here is always one path, never file contents.
        private static let maxRegexInputLength = 4096

        /// Whether this rule matches `relativePath`. A malformed regex, or a path longer than
        /// `maxRegexInputLength`, degrades to "doesn't match" rather than crashing or hanging —
        /// `validationError` is how a caller surfaces the malformed-pattern case as feedback
        /// instead of a silent no-op.
        func matches(_ relativePath: String) -> Bool {
            switch syntax {
            case .glob:
                return Glob(pattern).matches(relativePath)
            case .regex:
                guard relativePath.utf8.count <= Self.maxRegexInputLength,
                      let regex = try? NSRegularExpression(pattern: pattern) else { return false }
                let range = NSRange(relativePath.startIndex..., in: relativePath)
                return regex.firstMatch(in: relativePath, range: range) != nil
            }
        }

        /// `nil` when `pattern` is usable (always, for a glob rule); otherwise a message suitable
        /// for an inline validation error next to the pattern field.
        var validationError: String? {
            guard syntax == .regex else { return nil }
            do {
                _ = try NSRegularExpression(pattern: pattern)
                return nil
            } catch {
                return "Invalid regular expression: \(error.localizedDescription)"
            }
        }
    }
}
