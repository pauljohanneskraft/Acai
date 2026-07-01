require_relative 'media_item'
require_relative 'playable'

class Song < MediaItem
  include Playable

  attr_accessor :artist, :album

  def initialize(title, duration, artist, album)
    super(title, duration)
    @artist = artist
    @album = album
  end
end
