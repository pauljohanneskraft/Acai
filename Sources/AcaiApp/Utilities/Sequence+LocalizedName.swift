import Foundation

extension Sequence {
    func sorted(byLocalizedName name: (Element) -> String) -> [Element] {
        sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }
}
