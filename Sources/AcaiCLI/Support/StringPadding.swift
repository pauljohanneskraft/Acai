extension String {
    /// Returns the string padded with trailing spaces to at least `width` characters (left-aligned).
    /// Strings already at or beyond `width` are returned unchanged.
    func paddedTrailing(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    /// Returns the string padded with leading spaces to at least `width` characters (right-aligned).
    /// Strings already at or beyond `width` are returned unchanged.
    func paddedLeading(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
