package medialibrary

/** Shared base for every item in the library. */
open class MediaItem(
    override val title: String,
    override val duration: Double,
    val genre: Genre
) : Playable {
    override fun play() {
        println("Playing $title…")
    }
}
