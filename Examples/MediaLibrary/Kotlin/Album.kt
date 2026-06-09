package medialibrary

/** A released album: a titled, ordered set of tracks. */
data class Album(
    val title: String,
    val artist: String,
    val tracks: List<Track>
) {
    val totalLengthSeconds: Int
        get() = tracks.sumOf { it.lengthSeconds }
}
