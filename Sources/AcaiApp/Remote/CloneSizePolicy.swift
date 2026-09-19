import Foundation

/// When a clone is large enough to ask before taking its full history. Only a host that reports
/// a size up front (GitHub does) can trigger it; plain git has no way to tell before cloning.
struct CloneSizePolicy {
    let thresholdKilobytes: Int

    static let standard = CloneSizePolicy(thresholdKilobytes: 500_000)

    func warrantsWarning(sizeKilobytes: Int?) -> Bool {
        guard let sizeKilobytes else { return false }
        return sizeKilobytes > thresholdKilobytes
    }
}
