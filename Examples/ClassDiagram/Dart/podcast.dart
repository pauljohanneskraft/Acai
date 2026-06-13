import 'media_item.dart';
import 'playable.dart';

/// One episode of a podcast.
class Podcast extends MediaItem {
  Podcast(String title, double duration, this.host, this.episodeNumber)
      : super(title, duration, Genre.spokenWord);

  final String host;
  final int episodeNumber;

  @override
  void play() {
    print('🎙 Episode $episodeNumber: $title');
  }
}
