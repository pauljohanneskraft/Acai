import Foundation

/// The one spacing scale every Acai interface uses, rather than a magic number per view. Lives
/// here so the app and the widget extension share a scale instead of each keeping its own.
extension CGFloat {
    public static let spacingXXS: CGFloat = 2
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 12
    public static let spacingL: CGFloat = 16
    public static let spacingXL: CGFloat = 24
    public static let spacingXXL: CGFloat = 32
}
