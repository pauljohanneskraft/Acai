/// A compiled `*`/`?` glob pattern, anchored to the whole string. Kept dependency-free (no regex) so
/// a malformed pattern can never throw at evaluation time. Lives here rather than in any one module
/// so every consumer — a quality rule's type selector, a codebase's file allow/blocklist, a build
/// manifest's workspace pattern — shares one glob vocabulary instead of a second, incompatible
/// pattern matcher.
public struct Glob: Sendable {
    private let pattern: [Character]

    public init(_ pattern: String) {
        self.pattern = Array(pattern)
    }

    public func matches(_ value: String) -> Bool {
        let v = Array(value)
        var pi = 0, vi = 0
        var star = -1, mark = 0
        while vi < v.count {
            if pi < pattern.count, pattern[pi] == "?" || pattern[pi] == v[vi] {
                pi += 1; vi += 1
            } else if pi < pattern.count, pattern[pi] == "*" {
                star = pi; mark = vi; pi += 1
            } else if star != -1 {
                pi = star + 1; mark += 1; vi = mark
            } else {
                return false
            }
        }
        while pi < pattern.count, pattern[pi] == "*" { pi += 1 }
        return pi == pattern.count
    }
}
