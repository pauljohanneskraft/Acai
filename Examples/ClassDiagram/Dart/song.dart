import 'media_item.dart';
import 'playable.dart';

/// A single track by an artist.
class Song extends MediaItem {
  Song(String title, double duration, Genre genre, this.artist, [this.album])
      : super(title, duration, genre);

  final String artist;
  final String? album;

  @override
  void play() {
    print('♪ $artist — $title');
  }
}
