package medialibrary

/** Streams audio sources at a chosen quality. Depends on [Album] and [AudioSource]. */
class Streamer(private val quality: Quality) {

    var current: AudioSource? = null
        private set

    fun play(source: AudioSource) {
        current = source
        source.stream()
    }

    fun playAlbum(album: Album) {
        album.tracks.firstOrNull()?.let { play(it) }
    }
}
