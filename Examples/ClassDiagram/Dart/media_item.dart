import 'playable.dart';

/// Shared base for every item in the library.
class MediaItem implements Playable {
  MediaItem(this.title, this.duration, this.genre);

  @override
  final String title;
  @override
  final double duration;
  final Genre genre;

  @override
  void play() {
    print('Playing $title…');
  }
}
