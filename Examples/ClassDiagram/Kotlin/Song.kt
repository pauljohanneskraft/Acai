package medialibrary

/** A single track by an artist. */
class Song(
    title: String,
    duration: Double,
    genre: Genre,
    val artist: String,
    val album: String? = null
) : MediaItem(title, duration, genre) {
    override fun play() {
        println("♪ $artist — $title")
    }
}
