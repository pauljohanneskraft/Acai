import Foundation

/// Anything the player knows how to play.
public protocol Playable {
    var title: String { get }
    var duration: TimeInterval { get }

    func play()
}

/// A coarse classification for a piece of media.
public enum Genre {
    case pop
    case rock
    case jazz
    case classical
    case electronic
    case spokenWord
}
