import 'playlist.dart';

/// The user's whole collection: every playlist in one place.
class Library {
  Library([List<Playlist>? playlists]) : playlists = playlists ?? <Playlist>[];

  final List<Playlist> playlists;

  void addPlaylist(Playlist playlist) {
    playlists.add(playlist);
  }

  Playlist? playlist(String named) {
    for (final playlist in playlists) {
      if (playlist.name == named) return playlist;
    }
    return null;
  }
}
