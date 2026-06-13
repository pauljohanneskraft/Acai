package medialibrary

/** One episode of a podcast. */
class Podcast(
    title: String,
    duration: Double,
    val host: String,
    val episodeNumber: Int
) : MediaItem(title, duration, Genre.SPOKEN_WORD) {
    override fun play() {
        println("🎙 Episode $episodeNumber: $title")
    }
}
