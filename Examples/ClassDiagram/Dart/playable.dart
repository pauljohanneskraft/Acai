/// Anything the player knows how to play.
abstract class Playable {
  String get title;
  double get duration;

  void play();
}

/// A coarse classification for a piece of media.
enum Genre { pop, rock, jazz, classical, electronic, spokenWord }
