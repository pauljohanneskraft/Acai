import Foundation

/// The `UserDefaults` domain the diagram theme lives in: `.standard` for real users, and under a UI
/// test fixture a suite of its own per staging directory, so a journey's theme change never
/// reaches a real user's preference or another journey.
struct DiagramThemeStore {
    let suiteName: String?

    init(fixtureBaseDir: URL?) {
        suiteName = fixtureBaseDir.map {
            "de.kraftsoftware.Acai.uitest.\(StablePathDigest(path: $0.standardizedFileURL.path).hex)"
        }
    }

    var defaults: UserDefaults {
        guard let suiteName else { return .standard }
        return UserDefaults(suiteName: suiteName)
            ?? UserDefaults(suiteName: "de.kraftsoftware.Acai.uitest.fallback")!
    }

    var selection: DiagramThemeSelection {
        defaults.string(forKey: DiagramThemeSelection.storageKey).flatMap(DiagramThemeSelection.init) ?? .system
    }
}

/// FNV-1a, so the same path names the same suite on every launch (`hashValue` is seeded per process).
private struct StablePathDigest {
    let path: String

    var hex: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
