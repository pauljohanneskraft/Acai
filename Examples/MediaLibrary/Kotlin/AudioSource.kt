package medialibrary

/** Anything that can produce a stream of audio bytes. */
interface AudioSource {
    val title: String

    fun stream(): ByteArray
}

/** Streaming fidelity offered to the listener. */
enum class Quality {
    LOW,
    MEDIUM,
    HIGH,
    LOSSLESS
}
