package medialibrary

/** An ordered collection of media items the user has curated. */
class Playlist(val name: String, val items: MutableList<MediaItem> = mutableListOf()) {

    val totalDuration: Double
        get() = items.sumOf { it.duration }

    fun add(item: MediaItem) {
        items.add(item)
    }
}
