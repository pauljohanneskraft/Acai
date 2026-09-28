/// What Quick Open shows for a query over the entries it has indexed so far. A value rather than a
/// step, so a query typed before the index finished yields results the moment the entries land
/// instead of staying empty until the next keystroke.
struct QuickOpenSearch: Equatable {
    var entries: [QuickOpenEntry] = []
    var query: String = ""

    var results: [QuickOpenEntry] {
        guard !query.isEmpty else { return [] }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
