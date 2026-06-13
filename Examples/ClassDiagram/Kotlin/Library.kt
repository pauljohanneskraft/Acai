package medialibrary

/** The user's whole collection: every playlist in one place. */
class Library(val playlists: MutableList<Playlist> = mutableListOf()) {

    fun addPlaylist(playlist: Playlist) {
        playlists.add(playlist)
    }

    fun playlist(named: String): Playlist? = playlists.firstOrNull { it.name == named }
}
