/// One compiled `.gitignore` rule, matched against a path relative to the directory holding the
/// file it came from.
struct GitignorePattern: Sendable {

    enum Segment: Sendable {
        /// `**` — zero or more whole path components.
        case anyComponents
        case component(GitignoreSegment)
    }

    /// A leading `!`: a match re-includes the path instead of excluding it.
    let isNegated: Bool
    /// A trailing `/`: the rule only applies to directories.
    let matchesDirectoriesOnly: Bool
    /// A `/` anywhere but the end anchors the rule to the `.gitignore`'s own directory. An
    /// unanchored rule is a single component matched at any depth.
    let isAnchored: Bool
    let segments: [Segment]

    func matches(_ components: ArraySlice<Substring>, isDirectory: Bool) -> Bool {
        if matchesDirectoriesOnly, !isDirectory { return false }
        guard isAnchored else {
            guard let name = components.last, case .component(let segment)? = segments.first else { return false }
            return segments.count == 1 && segment.matches(name)
        }
        return matchesAnchored(components)
    }

    /// The component-level twin of ``GitignoreSegment/matches(_:)``, with `**` playing the part `*`
    /// plays there — one remembered fallback, so the walk stays linear in the path's depth.
    private func matchesAnchored(_ components: ArraySlice<Substring>) -> Bool {
        let path = Array(components)
        var segmentIndex = 0
        var pathIndex = 0
        var runSegment = -1
        var runPath = 0
        while pathIndex < path.count {
            if segmentIndex < segments.count, segments[segmentIndex].matches(path[pathIndex]) {
                segmentIndex += 1
                pathIndex += 1
            } else if segmentIndex < segments.count, segments[segmentIndex].isAnyComponents {
                runSegment = segmentIndex
                runPath = pathIndex
                segmentIndex += 1
            } else if runSegment >= 0 {
                segmentIndex = runSegment + 1
                runPath += 1
                pathIndex = runPath
            } else {
                return false
            }
        }
        while segmentIndex < segments.count, segments[segmentIndex].isAnyComponents { segmentIndex += 1 }
        return segmentIndex == segments.count
    }
}

extension GitignorePattern.Segment {
    var isAnyComponents: Bool {
        if case .anyComponents = self { return true }
        return false
    }

    func matches(_ component: Substring) -> Bool {
        if case .component(let segment) = self { return segment.matches(component) }
        return false
    }
}
