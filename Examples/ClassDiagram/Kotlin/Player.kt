package medialibrary

/** Drives playback over a library. Depends on [Library] and the [Playable] interface. */
class Player(private val library: Library) {

    var nowPlaying: Playable? = null
        private set

    fun play(item: Playable) {
        nowPlaying = item
        item.play()
    }

    fun playFirstItem(playlistNamed: String) {
        val item = library.playlist(playlistNamed)?.items?.firstOrNull() ?: return
        play(item)
    }
}
