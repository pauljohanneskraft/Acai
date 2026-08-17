import ArgumentParser

enum ReportFormatOption: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
}
