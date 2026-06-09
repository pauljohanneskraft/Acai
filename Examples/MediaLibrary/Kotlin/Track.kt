package medialibrary

/** Shared base for everything that can be streamed as a track. */
abstract class Track(
    override val title: String,
    val quality: Quality
) : AudioSource {

    abstract val lengthSeconds: Int

    override fun stream(): ByteArray = ByteArray(0)
}

/** A track captured live, with the venue it was recorded at. */
class LiveTrack(
    title: String,
    quality: Quality,
    override val lengthSeconds: Int,
    val venue: String
) : Track(title, quality)

/** A studio recording with a known release year. */
class RecordedTrack(
    title: String,
    quality: Quality,
    override val lengthSeconds: Int,
    val releaseYear: Int
) : Track(title, quality)
