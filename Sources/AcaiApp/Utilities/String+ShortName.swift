extension String {
    var shortName: String {
        split(separator: ".").last.map(String.init) ?? self
    }
}
