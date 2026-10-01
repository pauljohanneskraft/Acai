struct TOMLParseError: Error, Equatable {
    var line: Int
    var column: Int
    var message: String
}
