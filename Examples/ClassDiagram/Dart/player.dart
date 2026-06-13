import 'library.dart';
import 'playable.dart';

/// Drives playback over a library. Depends on [Library] and the [Playable] interface.
class Player {
  Player(this.library);

  final Library library;
  Playable? nowPlaying;

  void play(Playable item) {
    nowPlaying = item;
    item.play();
  }

  void playFirstItem(String playlistNamed) {
    final items = library.playlist(playlistNamed)?.items;
    if (items != null && items.isNotEmpty) {
      play(items.first);
    }
  }
}
