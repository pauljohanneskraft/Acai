import Foundation

extension Sequence {
    /// Ascending, case-insensitive order — the sort every codebase/diagram/project list in the
    /// sidebar and detail screens shares.
    func sorted(byLocalizedName name: (Element) -> String) -> [Element] {
        sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }
}
