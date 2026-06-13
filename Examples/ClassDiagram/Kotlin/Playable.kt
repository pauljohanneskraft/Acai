package medialibrary

/** Anything the player knows how to play. */
interface Playable {
    val title: String
    val duration: Double

    fun play()
}

/** A coarse classification for a piece of media. */
enum class Genre {
    POP,
    ROCK,
    JAZZ,
    CLASSICAL,
    ELECTRONIC,
    SPOKEN_WORD
}
