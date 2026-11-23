public protocol Playable {
    func play() -> Bool
}

public class Song: Playable {}
