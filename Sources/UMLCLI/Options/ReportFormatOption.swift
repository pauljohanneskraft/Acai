import ArgumentParser

/// Output format shared by the non-diagram report commands (`diff`, `check`): a human-readable
/// summary for the terminal, or machine-readable JSON for tooling.
enum ReportFormatOption: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
}
