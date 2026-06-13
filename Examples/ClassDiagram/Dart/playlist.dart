import 'media_item.dart';

/// An ordered collection of media items the user has curated.
class Playlist {
  Playlist(this.name, [List<MediaItem>? items]) : items = items ?? <MediaItem>[];

  final String name;
  final List<MediaItem> items;

  double get totalDuration =>
      items.fold(0, (sum, item) => sum + item.duration);

  void add(MediaItem item) {
    items.add(item);
  }
}
