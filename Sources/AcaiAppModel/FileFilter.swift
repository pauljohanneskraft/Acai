import Foundation
import AcaiQuality

/// A per-codebase, ordered file allow/blocklist, applied at indexing time so an excluded file is
/// never parsed.
public struct FileFilter: Codable, Hashable, Sendable {
    public var rules: [Rule]

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    /// Evaluates `rules` in order and takes the *last* match — `.gitignore`-style, so a later, more
    /// specific rule can override an earlier general one. No matching rule means "include."
    ///
    /// To scope a codebase down to only a subset, block everything first (`.block("*")`) then allow
    /// the subset — the same two-rule idiom `.gitignore` negation uses.
    public func includes(_ relativePath: String) -> Bool {
        var result = true
        for rule in rules where rule.matches(relativePath) {
            result = rule.action == .allow
        }
        return result
    }
}

extension FileFilter {
    public struct Rule: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID = UUID()
        public var pattern: String
        public var syntax: Syntax
        public var action: Action

        public enum Syntax: String, Codable, Hashable, Sendable, CaseIterable {
            case glob
            case regex
        }

        public enum Action: String, Codable, Hashable, Sendable, CaseIterable {
            case allow
            case block
        }

        public init(pattern: String, syntax: Syntax, action: Action) {
            self.pattern = pattern
            self.syntax = syntax
            self.action = action
        }

        /// Bounds regex input size to forecloses catastrophic-backtracking blowups tied to input
        /// length. Not a full guarantee, but the input here is always one path, never file contents.
        private static let maxRegexInputLength = 4096

        /// A malformed regex, or a path longer than `maxRegexInputLength`, degrades to "doesn't
        /// match" rather than crashing or hanging — `validationError` surfaces the malformed-pattern
        /// case separately instead of a silent no-op here.
        public func matches(_ relativePath: String) -> Bool {
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

        public var validationError: String? {
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
